import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../services/nearby_shops_service.dart';
import '../widgets/app_drawer.dart';
import '../widgets/community_check_shortcut.dart';
import '../widgets/nearby_shops_banner.dart';
import '../widgets/notification_bell.dart';
import '../widgets/premium_button.dart';
import 'account/account_center_screen.dart';
import 'community_check_screen.dart';
import 'create_request_cupertino_screen.dart';
import 'my_requests_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _tabIndex = 0;
  Map<String, dynamic>? _userProfile;
  String _currentCityName = LocationService.currentLocationNotifier.value?.city ?? 'Butuan City';
  String _currentBarangay = LocationService.currentLocationNotifier.value?.barangay ?? '';

  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  // Reported by MyRequestsScreen so the banner can collapse its onboarding
  // copy once the user already has something broadcasting — that pitch
  // is only useful before someone has sent their first Ping.
  final ValueNotifier<int> _activePingsCount = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    LocationService.currentLocationNotifier.addListener(_onLocationChanged);
    _loadProfile();
    _updateLocation();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    LocationService.currentLocationNotifier.removeListener(_onLocationChanged);
    _searchController.dispose();
    _activePingsCount.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _updateLocation();
    }
  }

  void _onLocationChanged() {
    final loc = LocationService.currentLocationNotifier.value;
    if (loc != null && mounted) {
      setState(() {
        _currentCityName = loc.city;
        _currentBarangay = loc.barangay;
      });
      NearbyShopsService.invalidateCache();
    }
  }

  Future<void> _loadProfile() async {
    final profile = await AuthService.getProfile();
    if (mounted) {
      setState(() {
        _userProfile = profile;
      });
    }
  }

  bool _isUpdatingLocation = false;

  Future<void> _updateLocation({bool forceRefresh = false}) async {
    if (mounted) setState(() => _isUpdatingLocation = true);
    try {
      final position = await LocationService.getCurrentPosition(forceRefresh: forceRefresh);
      if (position != null) {
        final locData = await LocationService.getCityAndBarangay(position.latitude, position.longitude);
        if (mounted) {
          setState(() {
            _currentCityName = locData['city'] ?? 'Current City';
            _currentBarangay = locData['barangay'] ?? '';
          });
          NearbyShopsService.invalidateCache();
          if (forceRefresh) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('📍 Location updated: ${locData['barangay']}, ${locData['city']}'),
                backgroundColor: const Color(0xFF004D40),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Location update error: $e');
    } finally {
      if (mounted) setState(() => _isUpdatingLocation = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userName = _userProfile?['full_name'] ?? AuthService.currentUser?.email ?? 'User';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      drawer: AppDrawer(
        isMerchantMode: false,
        currentTabIndex: _tabIndex,
        onTabSelected: (i) => setState(() => _tabIndex = i),
      ),
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: 0,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu_rounded, color: Color(0xFF004D40), size: 26),
            tooltip: 'Open Menu',
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: _isSearching
            ? Container(
                height: 40,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  onChanged: (val) => setState(() {}),
                  style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A)),
                  decoration: InputDecoration(
                    hintText: 'Search your Pings...',
                    hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18, color: Color(0xFF64748B)),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                          )
                        : null,
                  ),
                ),
              )
            : ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [Color(0xFF004D40), Color(0xFF10B981)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ).createShader(bounds),
                child: Text(
                  'Ping',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w900,
                    fontSize: 24,
                    letterSpacing: -0.8,
                    color: Colors.white,
                  ),
                ),
              ),
        actions: [
          const CommunityCheckShortcut(),
          if (_tabIndex == 0)
            IconButton(
              icon: Icon(
                _isSearching ? Icons.close_rounded : Icons.search_rounded,
                color: const Color(0xFF004D40),
              ),
              tooltip: _isSearching ? 'Close Search' : 'Search Pings',
              onPressed: () {
                setState(() {
                  if (_isSearching) {
                    _isSearching = false;
                    _searchController.clear();
                  } else {
                    _isSearching = true;
                  }
                });
              },
            ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFE2E8F0), height: 1),
        ),
      ),
      body: IndexedStack(
        index: _tabIndex,
        children: [
          // ── View 0: My Pings (Primary View) ─────────────────────────
          Column(
            children: [
              // Clean Header Banner
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ValueListenableBuilder<int>(
                        valueListenable: _activePingsCount,
                        builder: (context, activeCount, _) {
                          // Once a Ping is already broadcasting, the onboarding
                          // pitch is noise — a returning user needs status, not
                          // a re-explanation of what the app does.
                          if (activeCount > 0) {
                            return Row(
                              children: [
                                const Icon(Icons.bolt_rounded, size: 16, color: Color(0xFF10B981)),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '$activeCount Ping${activeCount > 1 ? 's' : ''} live — broadcasting to nearby shops',
                                    style: GoogleFonts.outfit(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            );
                          }
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Need parts, rooms, or a rider?',
                                style: GoogleFonts.outfit(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Broadcast your request to nearby verified shops in seconds.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF94A3B8),
                                  height: 1.3,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          InkWell(
                            onTap: _isUpdatingLocation ? null : () => _updateLocation(forceRefresh: true),
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.location_on_rounded, size: 11, color: Color(0xFF10B981)),
                                  const SizedBox(width: 4),
                                  Text(
                                    _currentBarangay.isNotEmpty
                                        ? '$_currentBarangay, $_currentCityName'
                                        : _currentCityName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  _isUpdatingLocation
                                      ? const SizedBox(
                                          width: 11,
                                          height: 11,
                                          child: CircularProgressIndicator(strokeWidth: 1.8, color: Colors.white),
                                        )
                                      : const Icon(Icons.refresh_rounded, size: 13, color: Colors.white70),
                                ],
                              ),
                            ),
                          ),
                          const Spacer(),
                          const NearbyShopsBanner(compact: true),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              // My Pings List
              Expanded(
                child: MyRequestsScreen(
                  searchQuery: _searchController.text,
                  activePingsNotifier: _activePingsCount,
                ),
              ),
            ],
          ),

          // ── View 1: Discover Categories Grid ────────────────────────
          CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Discover Categories',
                        style: GoogleFonts.outfit(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Select a category to quickly send a targeted Ping to local stores.',
                        style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverGrid.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.3,
                  children: const [
                    _CategoryCard(
                      title: 'Auto Parts & Supply',
                      subtitle: 'Car, Motorcycle & Truck Parts',
                      emoji: '🚗',
                      color: Color(0xFFEFF6FF),
                      dbCategory: 'Parts & Hardware',
                    ),
                    _CategoryCard(
                      title: 'Hardware & Supplies',
                      subtitle: 'Tools, Electrical, Plumbing',
                      emoji: '🔧',
                      color: Color(0xFFFEF3C7),
                      dbCategory: 'Parts & Hardware',
                    ),
                    _CategoryCard(
                      title: 'Rooms & Boarding',
                      subtitle: 'Bedspace, Apartments & Rooms',
                      emoji: '🏠',
                      color: Color(0xFFECFDF5),
                      dbCategory: 'Rooms & Boarding',
                    ),
                    _CategoryCard(
                      title: 'Express Rider',
                      subtitle: 'Errands, Pabili & Delivery',
                      emoji: '📦',
                      color: Color(0xFFF3E8FF),
                      dbCategory: 'Express Rider',
                    ),
                    _CategoryCard(
                      title: 'Food & Catering',
                      subtitle: 'Bulk Food, Snacks & Drinks',
                      emoji: '🍽️',
                      color: Color(0xFFFFF1F2),
                      dbCategory: 'Food & Catering',
                    ),
                    _CategoryCard(
                      title: 'Repair & Services',
                      subtitle: 'Aircon, Auto & Appliance',
                      emoji: '🛠️',
                      color: Color(0xFFF0FDF4),
                      dbCategory: 'Repair & Services',
                    ),
                    _CategoryCard(
                      title: 'General Store',
                      subtitle: 'Groceries, Supplies & Items',
                      emoji: '🏪',
                      color: Color(0xFFFEFCE8),
                      dbCategory: 'General Store',
                    ),
                    _CategoryCard(
                      title: 'Community Check',
                      subtitle: 'Roads, Floods & Traffic',
                      emoji: '📍',
                      color: Color(0xFFEEF2FF),
                      dbCategory: 'Community Check',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: Container(
        height: 68,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 20, offset: const Offset(0, -5)),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Left Action: Notification Bell
            const NotificationBell(),

            // Center Action: Send Ping FAB
            PremiumButton(
              onPressed: () {
                Navigator.of(context).push(
                  CupertinoPageRoute(
                    builder: (_) => const CreateRequestCupertinoScreen(),
                  ),
                );
              },
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 22),
              borderRadius: BorderRadius.circular(30),
              gradient: const LinearGradient(
                colors: [Color(0xFF004D40), Color(0xFF00695C)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: const [
                BoxShadow(color: Color(0x30004D40), blurRadius: 12, offset: Offset(0, 4)),
              ],
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bolt_rounded, size: 20, color: Color(0xFFFF8C42)),
                  SizedBox(width: 6),
                  Text(
                    'Send Ping',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                ],
              ),
            ),

            // Right Action: My Account Avatar
            GestureDetector(
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountCenterScreen(isMerchantMode: false)));
              },
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF004D40), width: 1.5),
                ),
                child: CircleAvatar(
                  radius: 14,
                  backgroundColor: const Color(0xFF004D40),
                  child: Text(
                    userName.isNotEmpty ? userName[0].toUpperCase() : 'P',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String emoji;
  final Color color;
  final String dbCategory;

  const _CategoryCard({
    required this.title,
    required this.subtitle,
    required this.emoji,
    required this.color,
    required this.dbCategory,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 15, offset: const Offset(0, 4)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (dbCategory == 'Community Check') {
              Navigator.push(context,
                MaterialPageRoute(builder: (_) => const CommunityCheckScreen()));
              return;
            }
            Navigator.of(context).push(
              CupertinoPageRoute(
                builder: (_) => CreateRequestCupertinoScreen(
                  initialCategory: dbCategory,
                ),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(emoji, style: const TextStyle(fontSize: 18)),
                ),
                const Spacer(),
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
