import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../services/privacy_blur_service.dart';
import 'location_picker_screen.dart';

/// How close a user needs to be to a check's target location to get a
/// nearby-notify alert. 100m is tighter than real-world GPS accuracy can
/// reliably support (especially indoors), so this favors actually reaching
/// people over strict precision.
const double kNotifyRadiusMeters = 500;

class CommunityCheckBottomSheet extends StatefulWidget {
  const CommunityCheckBottomSheet({super.key});

  @override
  State<CommunityCheckBottomSheet> createState() =>
      _CommunityCheckBottomSheetState();
}

class _CommunityCheckBottomSheetState extends State<CommunityCheckBottomSheet> {
  static const _types = [
    {'key': 'traffic', 'emoji': '🚦', 'label': 'Traffic'},
    {'key': 'queue',   'emoji': '👥', 'label': 'Queue Line'},
    {'key': 'flood',   'emoji': '🌊', 'label': 'Flood / Weather'},
    {'key': 'stock',   'emoji': '📦', 'label': 'Store Stock'},
  ];

  String _selectedType = 'traffic';
  final _landmarkController = TextEditingController();
  final _descController     = TextEditingController();
  final _bountyController   = TextEditingController();
  XFile? _photo;
  bool _isSubmitting = false;

  // ── Target location — where the check is ASKING ABOUT, which may be
  // nowhere near the poster's own GPS (e.g. asking about Masao while
  // physically in Libertad). Only a picked suggestion attaches real
  // coordinates, since that's what powers the notify-nearby step.
  Timer? _searchDebounce;
  List<Map<String, dynamic>> _suggestions = [];
  bool _isSearchingLocation = false;
  double? _targetLat;
  double? _targetLng;
  bool _isLocatingMe = false;

  void _onLandmarkChanged(String query) {
    if (_targetLat != null) {
      setState(() {
        _targetLat = null;
        _targetLng = null;
      });
    }
    _searchDebounce?.cancel();
    if (query.trim().length < 3) {
      setState(() => _suggestions = []);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 500), () => _searchLocation(query));
  }

  Future<void> _searchLocation(String query) async {
    setState(() => _isSearchingLocation = true);
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?format=jsonv2&limit=5&countrycodes=ph'
        '&q=${Uri.encodeComponent('$query, Butuan City, Philippines')}',
      );
      final res = await http.get(url, headers: {
        'User-Agent': 'iHanapApp/2.0 (contact@ihanap.ph)',
        'Accept-Language': 'en-US,en;q=0.9',
      }).timeout(const Duration(seconds: 5));

      if (res.statusCode == 200 && mounted) {
        final data = jsonDecode(res.body) as List;
        setState(() => _suggestions = data.cast<Map<String, dynamic>>());
      }
    } catch (_) {
      // Silent — free text still works without a picked location.
    } finally {
      if (mounted) setState(() => _isSearchingLocation = false);
    }
  }

  void _pickSuggestion(Map<String, dynamic> suggestion) {
    _landmarkController.text = suggestion['display_name'] as String? ?? _landmarkController.text;
    setState(() {
      _targetLat = double.tryParse(suggestion['lat']?.toString() ?? '');
      _targetLng = double.tryParse(suggestion['lon']?.toString() ?? '');
      _suggestions = [];
    });
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _isLocatingMe = true);
    try {
      // Goes through refreshLocation (not a raw GPS fetch) so this also
      // syncs to user_locations — the moment someone actively shares their
      // position here is the best signal we get for the nearby-notify RPC.
      final locData = await LocationService.refreshLocation(forceRefresh: true);
      if (locData == null || !mounted) return;
      if (locData.isMocked) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Mock location detected. Disable fake GPS apps to pin your location.'),
            backgroundColor: Color(0xFFDC2626),
          ),
        );
        return;
      }
      setState(() {
        _targetLat = locData.latitude;
        _targetLng = locData.longitude;
        _suggestions = [];
        if (_landmarkController.text.trim().isEmpty) {
          _landmarkController.text = '${locData.barangay}, ${locData.city}';
        }
      });
    } finally {
      if (mounted) setState(() => _isLocatingMe = false);
    }
  }

  Future<void> _openMapPicker() async {
    final picked = await Navigator.of(context).push<PickedLocation>(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(initialLat: _targetLat, initialLng: _targetLng),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _targetLat = picked.lat;
      _targetLng = picked.lng;
      _landmarkController.text = picked.label;
      _suggestions = [];
    });
  }

  /// Notifies only users the server finds within [radiusMeters] of the
  /// target point — clients never fetch anyone else's raw coordinates,
  /// the `nearby_user_ids` RPC returns matching ids only.
  Future<void> _notifyNearbyUsers({
    required String checkId,
    required String posterId,
    double radiusMeters = kNotifyRadiusMeters,
  }) async {
    if (_targetLat == null || _targetLng == null) return;
    try {
      final rows = await Supabase.instance.client.rpc('nearby_user_ids', params: {
        'target_lat': _targetLat,
        'target_lng': _targetLng,
        'radius_meters': radiusMeters,
      });

      final ids = (rows as List)
          .map((r) => r['user_id'] as String)
          .where((id) => id != posterId)
          .toList();
      if (ids.isEmpty) return;

      final typeLabel = _types.firstWhere((t) => t['key'] == _selectedType)['label'];
      final landmark = _landmarkController.text.trim();

      await Supabase.instance.client.from('notifications').insert(
        ids.map((id) => {
          'user_id': id,
          'title': '📍 Community Check nearby',
          'body': '$typeLabel check posted near $landmark — you\'re within ${kNotifyRadiusMeters.round()}m. Can you confirm?',
          'type': 'community_check_nearby',
          'reference_id': checkId,
        }).toList(),
      );
    } catch (e) {
      debugPrint('Failed to notify nearby users: $e');
    }
  }

  Future<void> _capturePhoto() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 75,
      maxWidth: 1280,
    );
    if (file != null && mounted) {
      setState(() => _photo = file);
    }
  }

  Future<void> _submit() async {
    if (_landmarkController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a landmark.')),
      );
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final userId = AuthService.currentUserId;
      if (userId == null) throw Exception('Not logged in');

      String? photoUrl;
      if (_photo != null) {
        final rawBytes = await _photo!.readAsBytes();
        
        // 🛡️ ON-DEVICE PRIVACY BLURRING (100% FREE - 0 Cloud API Cost)
        // Processes faces & vehicle plate zones in memory before network transfer
        final blurredBytes = await PrivacyBlurService.processPrivacyBlur(rawBytes);

        final path = 'checks/${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';

        await Supabase.instance.client.storage
            .from('community-check-photos')
            .uploadBinary(path, blurredBytes,
                fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true));

        photoUrl = Supabase.instance.client.storage
            .from('community-check-photos')
            .getPublicUrl(path);
      }

      final bounty = double.tryParse(_bountyController.text) ?? 0;

      final inserted = await Supabase.instance.client.from('community_checks').insert({
        'user_id':     userId,
        'check_type':  _selectedType,
        'landmark':    _landmarkController.text.trim(),
        'description': _descController.text.trim(),
        'bounty':      bounty,
        'photo_url':   photoUrl,
        if (_targetLat != null) 'target_lat': _targetLat,
        if (_targetLng != null) 'target_lng': _targetLng,
      }).select().single();

      await _notifyNearbyUsers(checkId: inserted['id'].toString(), posterId: userId);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ground check posted! Active for 15 minutes.'),
            backgroundColor: Color(0xFF004D40),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _landmarkController.dispose();
    _descController.dispose();
    _bountyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        top: 8, left: 20, right: 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(4)),
              ),
            ),
            const Text('Post a Ground Check',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF0F172A), letterSpacing: -0.3)),
            const SizedBox(height: 2),
            const Text('Share live conditions with your community',
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
            const SizedBox(height: 16),

            // Privacy banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: const Row(children: [
                Text('🛡️', style: TextStyle(fontSize: 14)),
                SizedBox(width: 8),
                Expanded(child: Text(
                  'Faces and vehicle license plates are auto-blurred for community safety.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF92400E), fontWeight: FontWeight.w600, height: 1.4),
                )),
              ]),
            ),
            const SizedBox(height: 16),

            // Check type
            const Text('TYPE OF CHECK',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: Color(0xFF94A3B8))),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: _types.map((t) {
                final isSelected = _selectedType == t['key'];
                return GestureDetector(
                  onTap: () => setState(() => _selectedType = t['key']!),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF004D40) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: isSelected ? const Color(0xFF004D40) : const Color(0xFFE2E8F0),
                          width: isSelected ? 2 : 1),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(t['emoji']!, style: const TextStyle(fontSize: 14)),
                      const SizedBox(width: 6),
                      Text(t['label']!, style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700,
                          color: isSelected ? Colors.white : const Color(0xFF334155))),
                    ]),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            // Landmark
            Row(
              children: [
                const Expanded(
                  child: Text('LANDMARK / LOCATION',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: Color(0xFF94A3B8))),
                ),
                Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  children: [
                    GestureDetector(
                      onTap: _openMapPicker,
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.map_rounded, size: 12, color: Color(0xFF004D40)),
                        SizedBox(width: 4),
                        Text('Pin on map',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF004D40))),
                      ]),
                    ),
                    GestureDetector(
                      onTap: _isLocatingMe ? null : _useCurrentLocation,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        _isLocatingMe
                            ? const SizedBox(width: 11, height: 11, child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF004D40)))
                            : const Icon(Icons.my_location_rounded, size: 12, color: Color(0xFF004D40)),
                        const SizedBox(width: 4),
                        const Text('Use my location',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF004D40))),
                      ]),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 6),
            _buildField(_landmarkController, 'e.g. J.P. Rizal St, near Jollibee',
              prefixIcon: const Icon(Icons.location_on_outlined, size: 18, color: Color(0xFF94A3B8)),
              suffixIcon: _isSearchingLocation
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : (_targetLat != null
                      ? const Icon(Icons.check_circle_rounded, size: 18, color: Color(0xFF10B981))
                      : null),
              onChanged: _onLandmarkChanged,
            ),

            // Suggestions dropdown
            if (_suggestions.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _suggestions.map((s) {
                    final name = s['display_name'] as String? ?? '';
                    return InkWell(
                      onTap: () => _pickSuggestion(s),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(children: [
                          const Icon(Icons.place_outlined, size: 15, color: Color(0xFF94A3B8)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(name,
                              maxLines: 2, overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, color: Color(0xFF334155))),
                          ),
                        ]),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],

            const SizedBox(height: 6),
            Row(children: [
              Icon(
                _targetLat != null ? Icons.gps_fixed_rounded : Icons.info_outline_rounded,
                size: 12,
                color: _targetLat != null ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _targetLat != null
                      ? 'Location pinned — neighbors within ${kNotifyRadiusMeters.round()}m will be notified.'
                      : 'Pin on map or pick a suggestion to notify neighbors within ${kNotifyRadiusMeters.round()}m.',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: _targetLat != null ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            _buildField(_descController, 'Additional details (optional)', maxLines: 2),
            const SizedBox(height: 10),
            _buildField(_bountyController, 'Tip bounty (optional)',
              keyboardType: TextInputType.number,
              prefixWidget: const Padding(
                padding: EdgeInsets.only(left: 12, right: 8),
                child: Text('₱', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF004D40))),
              )),
            const SizedBox(height: 16),

            // Camera
            GestureDetector(
              onTap: _capturePhoto,
              child: Container(
                height: _photo == null ? 90 : 160,
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _photo == null ? const Color(0xFFE2E8F0) : const Color(0xFF004D40),
                    width: _photo == null ? 1.5 : 2,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: _photo == null
                    ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(color: const Color(0xFFE2F0F0), borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.camera_alt_outlined, size: 20, color: Color(0xFF004D40)),
                        ),
                        const SizedBox(height: 6),
                        const Text('Take a Live Photo',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF004D40))),
                        const Text('Gallery upload is disabled for freshness',
                          style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
                      ])
                    : Stack(fit: StackFit.expand, children: [
                        kIsWeb
                            ? Image.network(_photo!.path, fit: BoxFit.cover)
                            : Image.file(File(_photo!.path), fit: BoxFit.cover),
                        Positioned(top: 8, right: 8,
                          child: GestureDetector(
                            onTap: () => setState(() => _photo = null),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                              child: const Icon(Icons.close, color: Colors.white, size: 14),
                            ),
                          )),
                        Positioned(bottom: 8, left: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                            child: const Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.blur_on, color: Colors.white, size: 12),
                              SizedBox(width: 4),
                              Text('Privacy filters applied',
                                style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                            ]),
                          )),
                      ]),
              ),
            ),
            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: _isSubmitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF004D40),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 46),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _isSubmitting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Post Ground Check', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(
    TextEditingController ctrl,
    String hint, {
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    Widget? prefixIcon,
    Widget? prefixWidget,
    Widget? suffixIcon,
    void Function(String)? onChanged,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFF004D40), width: 2),
    );
    return TextFormField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboardType,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFCBD5E1)),
        prefixIcon: prefixWidget ?? prefixIcon,
        prefixIconConstraints: prefixWidget != null ? const BoxConstraints(minWidth: 36, minHeight: 0) : null,
        suffixIcon: suffixIcon,
        contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        border: border, enabledBorder: border, focusedBorder: focusedBorder,
      ),
    );
  }
}
