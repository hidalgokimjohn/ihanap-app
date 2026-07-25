import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/auth_service.dart';
import '../auth_screen.dart';
import '../role_selection_screen.dart';
import 'edit_profile_screen.dart';
import 'manage_shops_screen.dart';
import 'security_screen.dart';

class AccountCenterScreen extends StatefulWidget {
  const AccountCenterScreen({super.key});

  @override
  State<AccountCenterScreen> createState() => _AccountCenterScreenState();
}

class _AccountCenterScreenState extends State<AccountCenterScreen> {
  Map<String, dynamic>? _profile;
  bool _isLoading = true;

  int _pingCount = 0;
  int _offerCount = 0;
  int _shopCount = 0;

  @override
  void initState() {
    super.initState();
    _fetchAccountData();
  }

  Future<void> _fetchAccountData() async {
    final userId = AuthService.currentUserId;
    if (userId == null) return;

    try {
      final profileData = await AuthService.getProfile(userId, true);

      // Fetch live stats in parallel
      final pingsResponse = await Supabase.instance.client
          .from('requests')
          .select('id')
          .eq('user_id', userId);

      final shopsResponse = await Supabase.instance.client
          .from('responders')
          .select('id')
          .eq('profile_id', userId);

      final shopsList = List<Map<String, dynamic>>.from(shopsResponse);
      int totalOffers = 0;
      if (shopsList.isNotEmpty) {
        final shopNames = shopsList.map((s) => s['shop_name'] as String).toList();
        final offersResponse = await Supabase.instance.client
            .from('offers')
            .select('id')
            .inFilter('shop_name', shopNames);
        totalOffers = (offersResponse as List).length;
      }

      if (mounted) {
        setState(() {
          _profile = profileData;
          _pingCount = (pingsResponse as List).length;
          _shopCount = shopsList.length;
          _offerCount = totalOffers;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Log Out of Ping?', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
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

    if (confirm != true || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: Color(0xFF004D40)),
      ),
    );

    await AuthService.signOut();

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (route) => false,
    );
  }

  void _showHelpGuide() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(28),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Row(
                children: [
                  Text('⚡ ', style: TextStyle(fontSize: 24)),
                  Text(
                    'How Ping Works',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildHelpStep(
                number: '1',
                title: 'Broadcast Your Ping',
                desc: 'Describe what auto parts, hardware, food, or service you need and set your maximum budget.',
              ),
              _buildHelpStep(
                number: '2',
                title: 'Receive Real-Time Offers',
                desc: 'Nearby shops and registered helpers get notified instantly and respond with pricing & stock info.',
              ),
              _buildHelpStep(
                number: '3',
                title: 'Accept & Claim',
                desc: 'Accept your favorite offer to receive a secure claim code for store pick-up or fast delivery.',
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF004D40),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Got it!', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHelpStep({required String number, required String title, required String desc}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              color: Color(0xFFE2F0F0),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF004D40), fontSize: 13),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A))),
                const SizedBox(height: 2),
                Text(desc, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.bolt_rounded, color: Color(0xFF004D40), size: 28),
            SizedBox(width: 8),
            Text('About Ping', style: TextStyle(fontWeight: FontWeight.w900)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ping App v1.0.0 (Build 2026)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            SizedBox(height: 6),
            Text('Broadcast to local shops in seconds.', style: TextStyle(color: Color(0xFF004D40), fontWeight: FontWeight.w600, fontSize: 12)),
            SizedBox(height: 12),
            Text(
              'Ping connects buyers directly with verified local auto supply stores, hardware shops, room providers, and community helpers in Butuan City.',
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B), height: 1.5),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF004D40))),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isDestructive ? const Color(0xFFFEF2F2) : const Color(0xFFE2F0F0),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: isDestructive ? const Color(0xFFEF4444) : const Color(0xFF004D40), size: 20),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 14,
          color: isDestructive ? const Color(0xFFEF4444) : const Color(0xFF0F172A),
        ),
      ),
      subtitle: subtitle != null
          ? Text(subtitle, style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)))
          : null,
      trailing: const Icon(Icons.chevron_right, color: Color(0xFFCBD5E1), size: 20),
      onTap: onTap,
    );
  }

  Widget _buildStatCard({required String count, required String label, required IconData icon}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: const [
            BoxShadow(color: Color(0x05000000), blurRadius: 8, offset: Offset(0, 2)),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: const Color(0xFF004D40)),
            const SizedBox(height: 6),
            Text(count, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String fullName = _profile?['full_name'] ?? 'User';
    final String email = _profile?['email'] ?? AuthService.currentUser?.email ?? 'No email set';
    final String contact = _profile?['contact_number'] ?? 'No phone added';
    final String barangay = _profile?['barangay'] ?? 'Butuan City';
    final String role = _profile?['primary_role'] ?? 'buyer';
    final String initial = fullName.isNotEmpty ? fullName[0].toUpperCase() : 'P';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Account Center', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Color(0xFF004D40)))
        : RefreshIndicator(
            color: const Color(0xFF004D40),
            onRefresh: _fetchAccountData,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Header Profile Card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: const [
                      BoxShadow(color: Color(0x05000000), blurRadius: 10, offset: Offset(0, 2)),
                    ],
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 34,
                        backgroundColor: const Color(0xFF004D40),
                        child: Text(
                          initial,
                          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              fullName,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              email,
                              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
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
                                    role == 'responder' ? '🏪 Merchant' : '🛍️ Buyer',
                                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFD97706)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 16),

                // Stats Dashboard Row
                Row(
                  children: [
                    _buildStatCard(count: '$_pingCount', label: 'My Pings', icon: Icons.bolt_rounded),
                    const SizedBox(width: 12),
                    _buildStatCard(count: '$_offerCount', label: 'Offers Sent', icon: Icons.local_offer_outlined),
                    const SizedBox(width: 12),
                    _buildStatCard(count: '$_shopCount', label: 'Shops Owned', icon: Icons.storefront_outlined),
                  ],
                ),

                const SizedBox(height: 24),
                
                // Account Settings Group
                const Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 8),
                  child: Text('ACCOUNT MANAGEMENT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF64748B), letterSpacing: 0.8)),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      _buildMenuTile(
                        icon: Icons.person_outline,
                        title: 'Edit Profile',
                        subtitle: 'Update name, contact ($contact), and barangay',
                        onTap: () async {
                          final updated = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const EditProfileScreen()));
                          if (updated == true) _fetchAccountData();
                        },
                      ),
                      const Divider(height: 1, color: Color(0xFFF1F5F9)),
                      _buildMenuTile(
                        icon: Icons.storefront_outlined,
                        title: 'Manage Shops',
                        subtitle: 'Register, edit, or remove merchant shop profiles',
                        onTap: () async {
                          await Navigator.push(context, MaterialPageRoute(builder: (_) => const ManageShopsScreen()));
                          _fetchAccountData();
                        },
                      ),
                      const Divider(height: 1, color: Color(0xFFF1F5F9)),
                      _buildMenuTile(
                        icon: Icons.lock_outline,
                        title: 'Security & Password',
                        subtitle: 'Update password and authentication settings',
                        onTap: () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const SecurityScreen()));
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Preferences & Help Group
                const Padding(
                  padding: EdgeInsets.only(left: 4, bottom: 8),
                  child: Text('PREFERENCES & SUPPORT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF64748B), letterSpacing: 0.8)),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      _buildMenuTile(
                        icon: Icons.swap_horiz_rounded,
                        title: 'Switch Role Preference',
                        subtitle: 'Change default view between Buyer and Merchant',
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => RoleSelectionScreen(
                                onRoleSelected: () => Navigator.pop(context),
                              ),
                            ),
                          );
                          _fetchAccountData();
                        },
                      ),
                      const Divider(height: 1, color: Color(0xFFF1F5F9)),
                      _buildMenuTile(
                        icon: Icons.help_outline_rounded,
                        title: 'How Ping Works',
                        subtitle: 'Learn about broadcasting Pings and claim codes',
                        onTap: _showHelpGuide,
                      ),
                      const Divider(height: 1, color: Color(0xFFF1F5F9)),
                      _buildMenuTile(
                        icon: Icons.info_outline_rounded,
                        title: 'About Ping',
                        subtitle: 'Version 1.0.0 • Terms & Information',
                        onTap: _showAboutDialog,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Destructive Group
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: _buildMenuTile(
                    icon: Icons.logout_rounded,
                    title: 'Log Out',
                    subtitle: 'Sign out of your Ping account',
                    isDestructive: true,
                    onTap: _handleLogout,
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
    );
  }
}
