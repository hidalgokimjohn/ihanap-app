import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/auth_service.dart';

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
    if (userId == null) return;
    try {
      final data = await Supabase.instance.client
          .from('shops')
          .select()
          .eq('user_id', userId)
          .order('created_at');
      if (mounted) {
        setState(() {
          _shops = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _editShop(Map<String, dynamic> shop) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => EditSingleShopScreen(shop: shop))).then((_) => _fetchShops());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Manage Shops', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF004D40)))
        : _shops.isEmpty
            ? const Center(child: Text('You have no shops.'))
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _shops.length,
                itemBuilder: (context, index) {
                  final shop = _shops[index];
                  return Card(
                    color: Colors.white,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFFE2F0F0),
                        child: Text(shop['shop_name'][0].toUpperCase(), style: const TextStyle(color: Color(0xFF004D40), fontWeight: FontWeight.bold)),
                      ),
                      title: Text(shop['shop_name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(shop['tagline'] ?? 'No tagline'),
                      trailing: const Icon(Icons.edit, color: Color(0xFF94A3B8)),
                      onTap: () => _editShop(shop),
                    ),
                  );
                },
              ),
    );
  }
}

class EditSingleShopScreen extends StatefulWidget {
  final Map<String, dynamic> shop;
  const EditSingleShopScreen({super.key, required this.shop});

  @override
  State<EditSingleShopScreen> createState() => _EditSingleShopScreenState();
}

class _EditSingleShopScreenState extends State<EditSingleShopScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _taglineController;
  late String _responderType;
  bool _isSaving = false;

  final List<String> _types = ['Auto Parts & Repair', 'Express Rider', 'Rooms & Boarding', 'Community Service'];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.shop['shop_name']);
    _taglineController = TextEditingController(text: widget.shop['tagline'] ?? '');
    _responderType = _types.contains(widget.shop['responder_type']) ? widget.shop['responder_type'] : _types[0];
  }

  Future<void> _saveShop() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      await Supabase.instance.client.from('shops').update({
        'shop_name': _nameController.text.trim(),
        'tagline': _taglineController.text.trim(),
        'responder_type': _responderType,
      }).eq('id', widget.shop['id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Shop updated successfully!')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('Edit Shop', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Shop Name', border: OutlineInputBorder()),
                validator: (val) => val == null || val.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                value: _responderType,
                decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
                items: _types.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (val) { if (val != null) setState(() => _responderType = val); },
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _taglineController,
                decoration: const InputDecoration(labelText: 'Tagline', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: _isSaving ? null : _saveShop,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF004D40),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _isSaving 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Save Shop', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
