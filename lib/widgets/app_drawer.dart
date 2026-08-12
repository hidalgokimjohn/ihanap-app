import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../screens/account/account_center_screen.dart';
import '../screens/account/manage_shops_screen.dart';
import '../screens/auth_screen.dart';
import '../screens/home_screen.dart';
import '../screens/responder_registration_screen.dart';
import '../screens/seller_screen.dart';
import '../services/auth_service.dart';

class AppDrawer extends StatefulWidget {
  final bool isMerchantMode;
  final int currentTabIndex;
  final Function(int) onTabSelected;

  const AppDrawer({
    super.key,
    required this.isMerchantMode,
    required this.currentTabIndex,
    required this.onTabSelected,
  });

  @override
  State<AppDrawer> createState() => _AppDrawerState();
}

class _AppDrawerState extends State<AppDrawer> {
  Map<String, dynamic>? _profile;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    final profile = await AuthService.getProfile();
    if (mounted) {
      setState(() => _profile = profile);
    }
  }

  Future<void> _handleRoleSwitch() async {
    final targetRole = widget.isMerchantMode ? 'buyer' : 'responder';
    final userId = AuthService.currentUserId;
    if (userId == null) return;

    final navigator = Navigator.of(context, rootNavigator: true);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      if (targetRole == 'responder') {
        final shopsData = await Supabase.instance.client
            .from('responders')
            .select()
            .eq('profile_id', userId)
            .order('created_at', ascending: true);

        final shopList = List<Map<String, dynamic>>.from(shopsData);

        if (shopList.isNotEmpty) {
          final activeShop = shopList.first;
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('active_shop_id', activeShop['id'] ?? '');
          await prefs.setString('responder_shop_name', activeShop['shop_name'] ?? '');
          await prefs.setString('responder_type', activeShop['responder_type'] ?? '');
          await prefs.setString('responder_owner_name', activeShop['owner_name'] ?? '');

          await AuthService.updateProfile({'primary_role': 'responder'});

          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text('Switched to Merchant Mode (${activeShop['shop_name']})'),
              backgroundColor: const Color(0xFF004D40),
              behavior: SnackBarBehavior.floating,
            ),
          );

          // Direct navigation - zero redundant loading screens!
          navigator.pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const SellerScreen()),
            (route) => false,
          );
          return;
        } else {
          // User has no shop profiles yet -> close drawer & open registration
          navigator.pop();
          final registered = await navigator.push<bool>(
            MaterialPageRoute(builder: (_) => const ResponderRegistrationScreen()),
          );
          if (registered == true) {
            await AuthService.updateProfile({'primary_role': 'responder'});
            navigator.pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const SellerScreen()),
              (route) => false,
            );
          }
          return;
        }
      } else {
        // Direct switch to Buyer Mode
        await AuthService.updateProfile({'primary_role': 'buyer'});
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('Switched to Buyer Mode'),
            backgroundColor: Color(0xFF004D40),
            behavior: SnackBarBehavior.floating,
          ),
        );
        navigator.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      debugPrint('Error switching role: $e');
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Text('Failed to switch mode: $e'),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleLogout() async {
    // Capture the root navigator BEFORE any async gap or drawer dismissal —
    // once the drawer closes, this widget's own `context` gets deactivated,
    // so anything captured here must not depend on `context` afterward.
    final navigator = Navigator.of(context, rootNavigator: true);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Log Out of Ping?', style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text('Are you sure you want to sign out of your account?'),
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
            child: const Text('Log Out', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await AuthService.signOut();

    // Replaces the entire navigation stack, which also dismisses the
    // still-open drawer underneath — no separate pop needed.
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final String fullName = _profile?['full_name'] ?? 'Ping User';
    final String email = _profile?['email'] ?? AuthService.currentUser?.email ?? 'No email set';
    final String barangay = _profile?['barangay'] ?? 'Butuan City';
    final String initial = fullName.isNotEmpty ? fullName[0].toUpperCase() : 'P';

    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            // ── Compact Brand Header ─────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFF004D40),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.bolt_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 10),
                  ShaderMask(
                    shaderCallback: (bounds) => const LinearGradient(
                      colors: [Color(0xFF004D40), Color(0xFF10B981)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ).createShader(bounds),
                    child: Text(
                      'Ping',
                      style: GoogleFonts.outfit(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.6,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFF1F5F9)),

            // ── Navigation Options List ───────────────────────────────
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 12, top: 8, bottom: 8),
                    child: Text('NAVIGATION', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8), letterSpacing: 0.8)),
                  ),
                  if (!widget.isMerchantMode) ...[
                    _buildDrawerTile(
                      icon: Icons.receipt_long_outlined,
                      activeIcon: Icons.receipt_long,
                      title: 'My Pings',
                      subtitle: 'View your broadcasted Pings & status',
                      isSelected: widget.currentTabIndex == 0,
                      onTap: () {
                        Navigator.pop(context);
                        widget.onTabSelected(0);
                      },
                    ),
                    _buildDrawerTile(
                      icon: Icons.grid_view_outlined,
                      activeIcon: Icons.grid_view,
                      title: 'Discover Categories',
                      subtitle: 'Browse category cards & quick pings',
                      isSelected: widget.currentTabIndex == 1,
                      onTap: () {
                        Navigator.pop(context);
                        widget.onTabSelected(1);
                      },
                    ),
                  ] else ...[
                    _buildDrawerTile(
                      icon: Icons.dynamic_feed_outlined,
                      activeIcon: Icons.dynamic_feed,
                      title: 'Live Pings',
                      subtitle: 'Customer requests stream in Butuan City',
                      isSelected: widget.currentTabIndex == 0,
                      onTap: () {
                        Navigator.pop(context);
                        widget.onTabSelected(0);
                      },
                    ),
                    _buildDrawerTile(
                      icon: Icons.local_offer_outlined,
                      activeIcon: Icons.local_offer,
                      title: 'My Offers',
                      subtitle: 'Offers submitted by your shop',
                      isSelected: widget.currentTabIndex == 1,
                      onTap: () {
                        Navigator.pop(context);
                        widget.onTabSelected(1);
                      },
                    ),
                  ],

                  const Padding(
                    padding: EdgeInsets.only(left: 12, top: 16, bottom: 8),
                    child: Text('PREFERENCES & ACCOUNT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF94A3B8), letterSpacing: 0.8)),
                  ),

                  _buildDrawerTile(
                    icon: Icons.swap_horiz_rounded,
                    activeIcon: Icons.swap_horiz_rounded,
                    title: widget.isMerchantMode ? 'Switch to Buyer Mode' : 'Switch to Merchant Mode',
                    subtitle: widget.isMerchantMode ? 'Switch to Customer Dashboard' : 'Switch to Merchant Live Feed',
                    onTap: _handleRoleSwitch,
                  ),

                  if (widget.isMerchantMode)
                    _buildDrawerTile(
                      icon: Icons.storefront_outlined,
                      activeIcon: Icons.storefront,
                      title: 'Manage Shops',
                      subtitle: 'Add, edit, or remove shop profiles',
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const ManageShopsScreen()));
                      },
                    ),

                  _buildDrawerTile(
                    icon: Icons.person_outline,
                    activeIcon: Icons.person,
                    title: 'Account Center',
                    subtitle: 'Profile settings & security',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => AccountCenterScreen(isMerchantMode: widget.isMerchantMode)));
                    },
                  ),
                ],
              ),
            ),

            // ── Pinned User Info & Log Out Footer ─────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(builder: (_) => AccountCenterScreen(isMerchantMode: widget.isMerchantMode)));
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: const Color(0xFF004D40),
                              child: Text(
                                initial,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    fullName,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    email,
                                    style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8), size: 20),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE2F0F0),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '📍 $barangay',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF004D40)),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          widget.isMerchantMode ? '🏪 Merchant Mode' : '🛍️ Buyer Mode',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFD97706)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _handleLogout,
                      icon: const Icon(Icons.logout_rounded, size: 17, color: Color(0xFFEF4444)),
                      label: const Text('Log Out', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFFECACA)),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerTile({
    required IconData icon,
    required IconData activeIcon,
    required String title,
    String? subtitle,
    bool isSelected = false,
    required VoidCallback onTap,
  }) {
    final color = isSelected ? const Color(0xFF004D40) : const Color(0xFF334155);

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0xFFE2F0F0) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(isSelected ? activeIcon : icon, color: color, size: 22),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            color: color,
            fontSize: 14,
          ),
        ),
        subtitle: subtitle != null
            ? Text(subtitle, style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)))
            : null,
        onTap: onTap,
      ),
    );
  }
}
