import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import 'responder_registration_screen.dart';

class RoleSelectionScreen extends StatefulWidget {
  final VoidCallback onRoleSelected;
  const RoleSelectionScreen({super.key, required this.onRoleSelected});

  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  bool _isLoading = false;

  Future<void> _selectBuyerRole() async {
    setState(() => _isLoading = true);
    try {
      final user = AuthService.currentUser;
      if (user != null) {
        await AuthService.updateProfile({
          'primary_role': 'buyer',
          'full_name': user.userMetadata?['full_name'] ?? user.userMetadata?['name'] ?? 'User',
          'email': user.email ?? '',
        });
      }
      widget.onRoleSelected();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating role: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _selectMerchantRole() async {
    setState(() => _isLoading = true);
    try {
      final user = AuthService.currentUser;
      if (user == null) return;

      // Check if user already has registered shops
      final shopsData = await Supabase.instance.client
          .from('responders')
          .select()
          .eq('profile_id', user.id)
          .order('created_at', ascending: true);

      final shopList = List<Map<String, dynamic>>.from(shopsData);

      if (shopList.isNotEmpty) {
        // User already has shop(s), activate the first one
        final activeShop = shopList.first;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('active_shop_id', activeShop['id'] ?? '');
        await prefs.setString('responder_shop_name', activeShop['shop_name'] ?? '');
        await prefs.setString('responder_type', activeShop['responder_type'] ?? '');
        await prefs.setString('responder_owner_name', activeShop['owner_name'] ?? '');

        await AuthService.updateProfile({
          'primary_role': 'responder',
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Switched to Merchant mode (${activeShop['shop_name']})'),
              backgroundColor: const Color(0xFF004D40),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        widget.onRoleSelected();
        return;
      }
    } catch (e) {
      debugPrint('Error checking existing shops: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }

    // No shops found: open registration screen to create a new shop
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ResponderRegistrationScreen()),
    );

    if (result == true) {
      final user = AuthService.currentUser;
      if (user != null) {
        await AuthService.updateProfile({
          'primary_role': 'responder',
        });
      }
      widget.onRoleSelected();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = AuthService.currentUser;
    final name = user?.userMetadata?['full_name'] ?? user?.userMetadata?['name'] ?? 'there';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              // ── Welcome Header ─────────────────────────────────────────
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE2F0F0),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(Icons.bolt_rounded, size: 36, color: Color(0xFF004D40)),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Welcome, $name!',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'How do you plan to use Ping today?\nYou can always switch or change this later.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF64748B),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 36),

              if (_isLoading)
                const Center(
                  child: CircularProgressIndicator(color: Color(0xFF004D40)),
                )
              else
                Expanded(
                  child: Column(
                    children: [
                      // ── Buyer Card ───────────────────────────────────────
                      _RoleCard(
                        emoji: '🛍️',
                        title: 'Buyer / Requester',
                        subtitle: 'I want to send Pings and get offers from nearby stores & helpers.',
                        badgeText: 'Most Popular',
                        badgeColor: const Color(0xFFE2F0F0),
                        badgeTextColor: const Color(0xFF004D40),
                        borderColor: const Color(0xFF004D40),
                        onTap: _selectBuyerRole,
                      ),

                      const SizedBox(height: 16),

                      // ── Merchant Card ────────────────────────────────────
                      _RoleCard(
                        emoji: '🏪',
                        title: 'Merchant / Responder',
                        subtitle: 'I have a shop, auto parts store, room, or courier service to offer.',
                        badgeText: 'Business / Seller',
                        badgeColor: const Color(0xFFFFF3E0),
                        badgeTextColor: const Color(0xFFE28743),
                        borderColor: const Color(0xFFE28743),
                        onTap: _selectMerchantRole,
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
}

class _RoleCard extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final String badgeText;
  final Color badgeColor;
  final Color badgeTextColor;
  final Color borderColor;
  final VoidCallback onTap;

  const _RoleCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.badgeText,
    required this.badgeColor,
    required this.badgeTextColor,
    required this.borderColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: borderColor, width: 2),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 28)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: badgeColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      badgeText,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: badgeTextColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF64748B),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    'Continue as ${title.split('/').first.trim()}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: borderColor,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward_rounded, size: 16, color: borderColor),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
