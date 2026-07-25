import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ResponderRegistrationScreen extends StatefulWidget {
  /// If provided, we are EDITING an existing shop (not creating a new one).
  final Map<String, dynamic>? existingShop;

  const ResponderRegistrationScreen({super.key, this.existingShop});

  @override
  State<ResponderRegistrationScreen> createState() => _ResponderRegistrationScreenState();
}

class _ResponderRegistrationScreenState extends State<ResponderRegistrationScreen> {
  final _shopNameController    = TextEditingController();
  final _descriptionController = TextEditingController();

  String? _selectedType;
  bool _isSubmitting = false;

  bool get _isEditing => widget.existingShop != null;

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
      _descriptionController.text = widget.existingShop!['description'] ?? '';
      _selectedType               = widget.existingShop!['responder_type'];
    }
  }

  Future<void> _submit() async {
    final shopName = _shopNameController.text.trim();
    final desc     = _descriptionController.text.trim();

    if (shopName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your shop or business name.')),
      );
      return;
    }
    if (_selectedType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a responder category.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('User not logged in');

      final payload = <String, dynamic>{
        'shop_name':      shopName,
        'responder_type': _selectedType,
        'description':    desc.isNotEmpty ? desc : null,
        'profile_id':     user.id,
        'city_name':      'Butuan City',
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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Hero Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF004D40), Color(0xFF004F50)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Text('??', style: TextStyle(fontSize: 28)),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _isEditing ? 'Edit Shop Profile' : 'Add a Shop',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: Colors.white),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _isEditing
                          ? 'Update the details for this shop.'
                          : 'Register a new shop under your account to respond to customer requests.',
                      style: const TextStyle(fontSize: 13, color: Colors.white70, height: 1.5),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Category
              const Text('Shop Category',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text('Select the one category that best describes this shop.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
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
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: selected ? Colors.white : const Color(0xFF334155),
                            ),
                          ),
                          if (selected) ...[
                            const SizedBox(width: 6),
                            const Icon(Icons.check_circle, size: 14, color: Colors.white),
                          ],
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 28),

              // Shop Name
              _buildLabel('Shop / Business Name', required: true),
              const SizedBox(height: 8),
              _buildField(
                controller: _shopNameController,
                hint: 'e.g. TechHub Auto Supply',
                icon: Icons.storefront_outlined,
                caps: TextCapitalization.words,
              ),

              const SizedBox(height: 16),

              // Tagline
              _buildLabel('Short Tagline (optional)', required: false),
              const SizedBox(height: 4),
              const Text('Helps customers trust your offers.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
              const SizedBox(height: 8),
              TextField(
                controller: _descriptionController,
                maxLines: 2,
                style: const TextStyle(fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'e.g. Best prices on Wigo & Click parts in Butuan',
                  hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
                  contentPadding: const EdgeInsets.all(16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.white,
                ),
              ),

              const SizedBox(height: 32),

              // Submit
              ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF004D40),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: _isSubmitting
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(_isEditing ? Icons.save_outlined : Icons.add_business_outlined, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            _isEditing ? 'Save Changes' : 'Register This Shop',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text, {required bool required}) {
    return Row(
      children: [
        Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        if (required)
          const Text(' *', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFFE28743))),
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
      style: const TextStyle(fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
        prefixIcon: Icon(icon, color: const Color(0xFF64748B), size: 20),
        contentPadding: const EdgeInsets.all(16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        filled: true,
        fillColor: Colors.white,
      ),
    );
  }
}
