import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/auth_service.dart';
import '../responder_registration_screen.dart';

class ManageShopsScreen extends StatefulWidget {
  const ManageShopsScreen({super.key});

  @override
  State<ManageShopsScreen> createState() => _ManageShopsScreenState();
}

class _ManageShopsScreenState extends State<ManageShopsScreen> {
  List<Map<String, dynamic>> _shops = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchShops();
  }

  Future<void> _fetchShops() async {
    final userId = AuthService.currentUserId;
    if (userId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      final data = await Supabase.instance.client
          .from('responders')
          .select()
          .eq('profile_id', userId)
          .order('created_at', ascending: true);

      if (mounted) {
        setState(() {
          _shops = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addShop() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const ResponderRegistrationScreen()),
    );
    if (result == true) {
      _fetchShops();
    }
  }

  Future<void> _editShop(Map<String, dynamic> shop) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ResponderRegistrationScreen(existingShop: shop)),
    );
    if (result == true) {
      _fetchShops();
    }
  }

  Future<void> _deleteShop(Map<String, dynamic> shop) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Shop Profile?', style: TextStyle(fontWeight: FontWeight.w800)),
        content: Text('Are you sure you want to delete "${shop['shop_name']}"? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await Supabase.instance.client
          .from('responders')
          .delete()
          .eq('id', shop['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Shop deleted successfully.'),
            backgroundColor: Color(0xFF004D40),
            behavior: SnackBarBehavior.floating,
          ),
        );
        _fetchShops();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting shop: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  String _typeEmoji(String? type) {
    switch (type) {
      case 'auto_parts': return '🚗';
      case 'hardware':   return '🔧';
      case 'rooms':      return '🏠';
      case 'rider':      return '📦';
      case 'food':       return '🍽️';
      case 'repair':     return '🛠️';
      case 'community':  return '📍';
      default:           return '🏪';
    }
  }

  String _typeLabel(String? type) {
    switch (type) {
      case 'auto_parts': return 'Auto Parts Shop';
      case 'hardware':   return 'Hardware Store';
      case 'rooms':      return 'Room / Boarding';
      case 'rider':      return 'Rider / Courier';
      case 'food':       return 'Food & Catering';
      case 'repair':     return 'Repair & Services';
      case 'community':  return 'Community Helper';
      default:           return 'General Store';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Manage Shops', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _addShop,
            icon: const Icon(Icons.add_business_rounded, color: Color(0xFF004D40)),
            tooltip: 'Add New Shop',
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF004D40)))
          : _shops.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: const BoxDecoration(
                            color: Color(0xFFE2F0F0),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.storefront_outlined, size: 48, color: Color(0xFF004D40)),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'No Shops Registered Yet',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Register a shop profile to respond to buyer Pings in your area.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF64748B), height: 1.5),
                        ),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _addShop,
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Register A Shop', style: TextStyle(fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF004D40),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: _shops.length,
                  itemBuilder: (context, index) {
                    final shop = _shops[index];
                    final shopName = shop['shop_name'] ?? 'Shop';
                    final category = _typeLabel(shop['responder_type']);
                    final emoji = _typeEmoji(shop['responder_type']);
                    final tagline = shop['description'] ?? 'No tagline provided';
                    final contactNumber = (shop['contact_number'] ?? '').toString();
                    final address = (shop['address'] ?? '').toString();
                    final logoUrl = (shop['logo_url'] ?? '').toString();

                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        boxShadow: const [
                          BoxShadow(color: Color(0x05000000), blurRadius: 10, offset: Offset(0, 2)),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  clipBehavior: Clip.antiAlias,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE2F0F0),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: logoUrl.isNotEmpty
                                      ? Image.network(
                                          logoUrl,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => Center(child: Text(emoji, style: const TextStyle(fontSize: 22))),
                                        )
                                      : Center(child: Text(emoji, style: const TextStyle(fontSize: 22))),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        shopName,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        category,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF004D40),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => _editShop(shop),
                                  icon: const Icon(Icons.edit_outlined, color: Color(0xFF64748B), size: 20),
                                  tooltip: 'Edit Shop',
                                ),
                                IconButton(
                                  onPressed: () => _deleteShop(shop),
                                  icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444), size: 20),
                                  tooltip: 'Delete Shop',
                                ),
                              ],
                            ),
                            if (contactNumber.isNotEmpty || address.isNotEmpty || tagline.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              const Divider(height: 1, color: Color(0xFFF1F5F9)),
                              const SizedBox(height: 12),
                            ],
                            if (contactNumber.isNotEmpty) ...[
                              Row(
                                children: [
                                  const Icon(Icons.phone_rounded, size: 14, color: Color(0xFF004D40)),
                                  const SizedBox(width: 6),
                                  Text(
                                    contactNumber,
                                    style: const TextStyle(fontSize: 13, color: Color(0xFF004D40), fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                              if (address.isNotEmpty || tagline.isNotEmpty) const SizedBox(height: 8),
                            ],
                            if (address.isNotEmpty) ...[
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.location_on_rounded, size: 14, color: Color(0xFF64748B)),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      address,
                                      style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
                              if (tagline.isNotEmpty) const SizedBox(height: 8),
                            ],
                            if (tagline.isNotEmpty)
                              Text(
                                tagline,
                                style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), fontStyle: FontStyle.italic),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: _shops.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _addShop,
              backgroundColor: const Color(0xFF004D40),
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_business_rounded),
              label: const Text('Add Shop', style: TextStyle(fontWeight: FontWeight.bold)),
            )
          : null,
    );
  }
}
