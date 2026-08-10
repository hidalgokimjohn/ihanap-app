import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/location_service.dart';
import '../widgets/premium_button.dart';

class ResponderRegistrationScreen extends StatefulWidget {
  /// If provided, we are EDITING an existing shop (not creating a new one).
  final Map<String, dynamic>? existingShop;

  const ResponderRegistrationScreen({super.key, this.existingShop});

  @override
  State<ResponderRegistrationScreen> createState() => _ResponderRegistrationScreenState();
}

class _ResponderRegistrationScreenState extends State<ResponderRegistrationScreen> {
  final _shopNameController    = TextEditingController();
  final _contactController     = TextEditingController();
  final _addressController     = TextEditingController();
  final _descriptionController = TextEditingController();

  String? _selectedType;
  bool _isSubmitting = false;

  XFile? _photo;
  String? _existingLogoUrl;
  bool _photoRemoved = false;

  bool get _isEditing => widget.existingShop != null;
  bool get _hasPhoto => _photo != null || (!_photoRemoved && (_existingLogoUrl ?? '').isNotEmpty);

  final List<Map<String, String>> _responderTypes = [
    {'emoji': '🚗', 'label': 'Auto Parts Shop',   'value': 'auto_parts'},
    {'emoji': '🔧', 'label': 'Hardware Store',     'value': 'hardware'},
    {'emoji': '🏠', 'label': 'Room / Boarding',    'value': 'rooms'},
    {'emoji': '📦', 'label': 'Rider / Courier',    'value': 'rider'},
    {'emoji': '🏪', 'label': 'General Store',      'value': 'general'},
    {'emoji': '📍', 'label': 'Community Helper',   'value': 'community'},
    {'emoji': '🍽️', 'label': 'Food & Catering',   'value': 'food'},
    {'emoji': '🛠️', 'label': 'Repair & Services', 'value': 'repair'},
  ];

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _shopNameController.text    = widget.existingShop!['shop_name'] ?? '';
      _contactController.text     = widget.existingShop!['contact_number'] ?? '';
      _addressController.text     = widget.existingShop!['address'] ?? '';
      _descriptionController.text = widget.existingShop!['description'] ?? '';
      _selectedType               = widget.existingShop!['responder_type'];
      _existingLogoUrl            = widget.existingShop!['logo_url'];
    }
  }

  @override
  void dispose() {
    _shopNameController.dispose();
    _contactController.dispose();
    _addressController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _showPhotoOptions() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: Color(0xFF004D40)),
              title: Text('Take Photo', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: Color(0xFF004D40)),
              title: Text('Choose from Gallery', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600)),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
            if (_hasPhoto)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
                title: Text('Remove Photo', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, color: const Color(0xFFEF4444))),
                onTap: () => Navigator.pop(ctx, 'remove'),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (action == 'remove') {
      setState(() {
        _photo = null;
        _photoRemoved = true;
      });
      return;
    }

    if (action == 'camera' || action == 'gallery') {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: action == 'camera' ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 1280,
      );
      if (file != null && mounted) {
        setState(() {
          _photo = file;
          _photoRemoved = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    final shopName = _shopNameController.text.trim();
    final contact  = _contactController.text.trim();
    final address  = _addressController.text.trim();
    final desc     = _descriptionController.text.trim();

    if (shopName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your shop or service name.')),
      );
      return;
    }
    if (_selectedType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select what you offer.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('User not logged in');

      // Attach GPS coordinates from LocationService if available
      final loc = LocationService.currentLocationNotifier.value;

      // Upload a newly picked photo, or clear it if explicitly removed.
      // Otherwise omit the key so an unchanged existing photo is left alone.
      String? uploadedLogoUrl;
      bool logoChanged = false;
      if (_photo != null) {
        final bytes = await _photo!.readAsBytes();
        final path = 'shops/${user.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await Supabase.instance.client.storage
            .from('shop-photos')
            .uploadBinary(path, bytes, fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true));
        uploadedLogoUrl = Supabase.instance.client.storage.from('shop-photos').getPublicUrl(path);
        logoChanged = true;
      } else if (_photoRemoved) {
        uploadedLogoUrl = null;
        logoChanged = true;
      }

      final payload = <String, dynamic>{
        'shop_name':      shopName,
        'responder_type': _selectedType,
        'contact_number': contact.isNotEmpty ? contact : null,
        'address':        address.isNotEmpty ? address : null,
        'description':    desc.isNotEmpty ? desc : null,
        'profile_id':     user.id,
        'city_name':      loc?.city ?? 'Butuan City',
        if (loc != null) 'latitude':  loc.latitude,
        if (loc != null) 'longitude': loc.longitude,
        if (logoChanged) 'logo_url': uploadedLogoUrl,
      };

      // Silently fetch owner name from profile
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('full_name')
          .eq('id', user.id)
          .maybeSingle();
      final ownerName = profile?['full_name'] ?? user.email ?? 'Owner';
      payload['owner_name'] = ownerName;

      Map<String, dynamic> response;

      if (_isEditing) {
        response = await Supabase.instance.client
            .from('responders')
            .update(payload)
            .eq('id', widget.existingShop!['id'])
            .select()
            .single();
      } else {
        response = await Supabase.instance.client
            .from('responders')
            .insert(payload)
            .select()
            .single();
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('active_shop_id',      response['id']);
      await prefs.setString('responder_shop_name', shopName);
      await prefs.setString('responder_type',      _selectedType!);

      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          _isEditing ? 'Edit Shop Profile' : 'Add a Shop',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 17, color: const Color(0xFF0F172A)),
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFE2E8F0), height: 1),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Hero Header ─────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF004D40), Color(0xFF00695C)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: const [
                    BoxShadow(color: Color(0x28004D40), blurRadius: 20, offset: Offset(0, 8)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        _isEditing ? Icons.storefront_rounded : Icons.add_business_rounded,
                        size: 28,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _isEditing ? 'Edit Shop Profile' : 'Add a Shop',
                      style: GoogleFonts.outfit(fontSize: 23, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -0.5),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _isEditing
                          ? 'Update the details for this shop.'
                          : 'Register a shop or service under your account to respond to community Pings.',
                      style: GoogleFonts.plusJakartaSans(fontSize: 13, color: Colors.white.withValues(alpha: 0.8), height: 1.5),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── Shop Photo ──────────────────────────────────────────
              _buildPhotoPicker(),

              const SizedBox(height: 28),

              // ── Category ────────────────────────────────────────────
              Text('What Do You Offer?', style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A))),
              const SizedBox(height: 4),
              Text('Select the one category that best describes this shop.',
                  style: GoogleFonts.plusJakartaSans(fontSize: 12, color: const Color(0xFF64748B))),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _responderTypes.map((type) {
                  final selected = _selectedType == type['value'];
                  return GestureDetector(
                    onTap: () => setState(() => _selectedType = type['value']),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: selected ? const Color(0xFF004D40) : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected ? const Color(0xFF004D40) : const Color(0xFFE2E8F0),
                          width: selected ? 2 : 1,
                        ),
                        boxShadow: selected
                            ? [const BoxShadow(color: Color(0x20006A6B), blurRadius: 8, offset: Offset(0, 2))]
                            : [],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(type['emoji']!, style: const TextStyle(fontSize: 16)),
                          const SizedBox(width: 6),
                          Text(
                            type['label']!,
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: selected ? Colors.white : const Color(0xFF334155),
                            ),
                          ),
                          if (selected) ...[
                            const SizedBox(width: 6),
                            const Icon(Icons.check_circle_rounded, size: 14, color: Colors.white),
                          ],
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 28),

              // ── Shop Name ───────────────────────────────────────────
              _buildLabel('Shop / Service Name', required: true),
              const SizedBox(height: 8),
              _buildField(
                controller: _shopNameController,
                hint: 'e.g. TechHub Auto Supply or "Juan\'s Helping Hands"',
                icon: Icons.storefront_outlined,
                caps: TextCapitalization.words,
              ),

              const SizedBox(height: 16),

              // ── Contact Number ──────────────────────────────────────
              _buildLabel('Shop Contact Number (optional)', required: false),
              const SizedBox(height: 4),
              Text('Shown to customers instead of your personal number.',
                  style: GoogleFonts.plusJakartaSans(fontSize: 11, color: const Color(0xFF94A3B8))),
              const SizedBox(height: 8),
              _buildField(
                controller: _contactController,
                hint: '09XX-XXX-XXXX',
                icon: Icons.phone_outlined,
                keyboard: TextInputType.phone,
              ),

              const SizedBox(height: 16),

              // ── Address / Landmark ──────────────────────────────────
              _buildLabel('Address / Landmark (optional)', required: false),
              const SizedBox(height: 4),
              Text('Helps customers find you for pickup or visits.',
                  style: GoogleFonts.plusJakartaSans(fontSize: 11, color: const Color(0xFF94A3B8))),
              const SizedBox(height: 8),
              _buildField(
                controller: _addressController,
                hint: 'e.g. Purok 3, near Libertad Elementary School',
                icon: Icons.location_on_outlined,
                caps: TextCapitalization.sentences,
              ),

              const SizedBox(height: 16),

              // ── Tagline ─────────────────────────────────────────────
              _buildLabel('Short Tagline (optional)', required: false),
              const SizedBox(height: 4),
              Text('Helps customers trust your offers.',
                  style: GoogleFonts.plusJakartaSans(fontSize: 11, color: const Color(0xFF94A3B8))),
              const SizedBox(height: 8),
              TextField(
                controller: _descriptionController,
                maxLines: 2,
                style: GoogleFonts.plusJakartaSans(fontSize: 14, color: const Color(0xFF0F172A)),
                decoration: InputDecoration(
                  hintText: 'e.g. Best prices on Wigo & Click parts in Butuan',
                  hintStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFF94A3B8), fontSize: 13),
                  contentPadding: const EdgeInsets.all(16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: Color(0xFF004D40), width: 1.6),
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),

              const SizedBox(height: 32),

              // ── Submit ──────────────────────────────────────────────
              _buildGradientButton(
                onPressed: _isSubmitting ? null : _submit,
                isLoading: _isSubmitting,
                icon: _isEditing ? Icons.save_outlined : Icons.add_business_outlined,
                label: _isEditing ? 'Save Changes' : 'Register This Shop',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoPicker() {
    Widget content;
    if (_photo != null) {
      content = kIsWeb
          ? Image.network(_photo!.path, fit: BoxFit.cover)
          : Image.file(File(_photo!.path), fit: BoxFit.cover);
    } else if (!_photoRemoved && (_existingLogoUrl ?? '').isNotEmpty) {
      content = Image.network(_existingLogoUrl!, fit: BoxFit.cover);
    } else {
      content = Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.storefront_rounded, size: 28, color: Color(0xFFCBD5E1)),
          const SizedBox(height: 6),
          Text('Add Photo', style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF94A3B8))),
        ],
      );
    }

    return Center(
      child: GestureDetector(
        onTap: _showPhotoOptions,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 110,
              height: 110,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
              ),
              clipBehavior: Clip.antiAlias,
              child: content,
            ),
            Positioned(
              bottom: -4,
              right: -4,
              child: Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF004D40), Color(0xFF00695C)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                ),
                child: const Icon(Icons.camera_alt_rounded, size: 15, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text, {required bool required}) {
    return Row(
      children: [
        Text(text, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A))),
        if (required)
          Text(' *', style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, color: const Color(0xFFE28743))),
      ],
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType keyboard = TextInputType.text,
    TextCapitalization caps = TextCapitalization.none,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      textCapitalization: caps,
      style: GoogleFonts.plusJakartaSans(fontSize: 15, color: const Color(0xFF0F172A)),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.plusJakartaSans(color: const Color(0xFF94A3B8), fontSize: 13),
        prefixIcon: Icon(icon, color: const Color(0xFF64748B), size: 20),
        contentPadding: const EdgeInsets.all(16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF004D40), width: 1.6),
        ),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }

  Widget _buildGradientButton({
    required VoidCallback? onPressed,
    required bool isLoading,
    required IconData icon,
    required String label,
  }) {
    return PremiumButton(
      onPressed: onPressed,
      isLoading: isLoading,
      height: 56,
      gradient: const LinearGradient(
        colors: [Color(0xFF004D40), Color(0xFF00695C)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      boxShadow: const [BoxShadow(color: Color(0x33004D40), blurRadius: 14, offset: Offset(0, 6))],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
          ),
        ],
      ),
    );
  }
}
