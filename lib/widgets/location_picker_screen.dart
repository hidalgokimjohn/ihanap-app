import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../services/location_service.dart';

/// Result of a map pin drop — precise coordinates plus a human-readable
/// label for the picked point.
class PickedLocation {
  final double lat;
  final double lng;
  final String label;
  const PickedLocation({required this.lat, required this.lng, required this.label});
}

/// Full-screen "drag the map, pin stays centered" location picker — the
/// same pattern rideshare/delivery apps use, since it's far more precise
/// than tapping a single point on a small map (no fat-finger error, and
/// the pin position is always exactly the screen center).
class LocationPickerScreen extends StatefulWidget {
  final double? initialLat;
  final double? initialLng;

  const LocationPickerScreen({super.key, this.initialLat, this.initialLng});

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  // Butuan City center — used when no GPS/initial point is available.
  static const _fallbackCenter = LatLng(8.9475, 125.5406);

  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  LatLng _center = _fallbackCenter;
  String _label = 'Move the map to pin a location';
  bool _isResolvingLabel = false;
  bool _isLocatingMe = false;
  Timer? _reverseDebounce;
  Timer? _searchDebounce;
  List<Map<String, dynamic>> _suggestions = [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialLat != null && widget.initialLng != null) {
      _center = LatLng(widget.initialLat!, widget.initialLng!);
      _reverseGeocode(_center);
    } else {
      _useCurrentLocation(recenter: true);
    }
  }

  @override
  void dispose() {
    _reverseDebounce?.cancel();
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onMapEvent(MapEvent event) {
    _center = event.camera.center;
    _reverseDebounce?.cancel();
    _reverseDebounce = Timer(const Duration(milliseconds: 600), () => _reverseGeocode(_center));
  }

  Future<void> _reverseGeocode(LatLng point) async {
    setState(() => _isResolvingLabel = true);
    try {
      final locData = await LocationService.getCityAndBarangay(point.latitude, point.longitude);
      if (!mounted) return;
      setState(() {
        _label = '${locData['barangay']}, ${locData['city']}';
      });
    } finally {
      if (mounted) setState(() => _isResolvingLabel = false);
    }
  }

  Future<void> _useCurrentLocation({bool recenter = false}) async {
    setState(() => _isLocatingMe = true);
    try {
      // Goes through refreshLocation (not a raw GPS fetch) so this also
      // syncs to user_locations for the nearby-notify RPC.
      final locData = await LocationService.refreshLocation(forceRefresh: true);
      if (locData == null || !mounted) return;
      if (locData.isMocked) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Mock location detected — showing Butuan City instead. Drag the map to pin manually.'),
            backgroundColor: Color(0xFFDC2626),
          ),
        );
        return;
      }
      final point = LatLng(locData.latitude, locData.longitude);
      _mapController.move(point, 17);
      if (recenter) {
        setState(() {
          _center = point;
          _label = '${locData.barangay}, ${locData.city}';
        });
      }
    } finally {
      if (mounted) setState(() => _isLocatingMe = false);
    }
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    if (query.trim().length < 3) {
      setState(() => _suggestions = []);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 500), () => _searchLocation(query));
  }

  Future<void> _searchLocation(String query) async {
    setState(() => _isSearching = true);
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
      // Silent — dragging the map still works without search.
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  void _jumpToSuggestion(Map<String, dynamic> suggestion) {
    final lat = double.tryParse(suggestion['lat']?.toString() ?? '');
    final lng = double.tryParse(suggestion['lon']?.toString() ?? '');
    if (lat == null || lng == null) return;
    final point = LatLng(lat, lng);
    _mapController.move(point, 17);
    setState(() {
      _center = point;
      _label = suggestion['display_name'] as String? ?? _label;
      _suggestions = [];
    });
    _searchController.clear();
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 16,
              onMapEvent: _onMapEvent,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'ph.ihanap.app',
              ),
            ],
          ),

          // Fixed center pin — the map moves beneath it, so this is always
          // the exact point that gets picked.
          const IgnorePointer(
            child: Center(
              child: Padding(
                padding: EdgeInsets.only(bottom: 36),
                child: Icon(Icons.location_on_rounded, size: 44, color: Color(0xFFDC2626)),
              ),
            ),
          ),

          // Top bar: back button + search
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Column(
                children: [
                  Row(
                    children: [
                      _RoundIconButton(
                        icon: Icons.arrow_back_ios_new_rounded,
                        onTap: () => Navigator.of(context).pop(),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, 3)),
                            ],
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.search_rounded, size: 18, color: Color(0xFF94A3B8)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _searchController,
                                  onChanged: _onSearchChanged,
                                  style: const TextStyle(fontSize: 13),
                                  decoration: const InputDecoration(
                                    hintText: 'Search a place to jump to it',
                                    hintStyle: TextStyle(fontSize: 13, color: Color(0xFFCBD5E1)),
                                    border: InputBorder.none,
                                    isDense: true,
                                  ),
                                ),
                              ),
                              if (_isSearching)
                                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_suggestions.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, 3)),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: _suggestions.map((s) {
                          final name = s['display_name'] as String? ?? '';
                          return InkWell(
                            onTap: () => _jumpToSuggestion(s),
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
                ],
              ),
            ),
          ),

          // Recenter-to-me button
          Positioned(
            right: 12,
            bottom: 150,
            child: _RoundIconButton(
              icon: Icons.my_location_rounded,
              loading: _isLocatingMe,
              onTap: _isLocatingMe ? null : () => _useCurrentLocation(recenter: true),
            ),
          ),

          // Bottom confirm card
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 16, offset: const Offset(0, 6)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.location_on_rounded, size: 16, color: Color(0xFFDC2626)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _isResolvingLabel
                              ? const Text('Locating…', style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8), fontStyle: FontStyle.italic))
                              : Text(_label,
                                  maxLines: 2, overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop(PickedLocation(lat: _center.latitude, lng: _center.longitude, label: _label));
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF004D40),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 44),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Pin This Location', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool loading;

  const _RoundIconButton({required this.icon, required this.onTap, this.loading = false});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: loading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF004D40)))
              : Icon(icon, size: 18, color: const Color(0xFF004D40)),
        ),
      ),
    );
  }
}
