import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../widgets/offer_bottom_sheet.dart';
import '../widgets/order_summary_sheet.dart';
import '../widgets/notification_bell.dart';
import '../widgets/app_drawer.dart';
import 'package:google_fonts/google_fonts.dart';
import 'account/account_center_screen.dart';
import 'responder_registration_screen.dart';
import 'my_offers_screen.dart';

class SellerScreen extends StatefulWidget {
  const SellerScreen({super.key});

  @override
  State<SellerScreen> createState() => _SellerScreenState();
}

class _SellerScreenState extends State<SellerScreen> with WidgetsBindingObserver {
  String _currentCityName = LocationService.currentLocationNotifier.value?.city ?? 'Butuan City';
  Position? _currentPosition;

  List<Map<String, dynamic>> _shops = [];
  int _activeShopIndex = 0;
  bool _profileLoaded = false;
  bool _showAll = true;
  int _tabIndex = 0; // 0 = Live Requests, 1 = My Offers

  Map<String, dynamic>? get _activeShop =>
      _shops.isNotEmpty ? _shops[_activeShopIndex] : null;

  List<String> _matchingCategories() {
    final type = _activeShop?['responder_type'];
    switch (type) {
      case 'auto_parts': return ['Parts & Hardware'];
      case 'hardware':   return ['Parts & Hardware'];
      case 'rooms':      return ['Rooms & Boarding'];
      case 'rider':      return ['Express Rider'];
      case 'food':       return ['Food & Catering'];
      case 'repair':     return ['Repair & Services'];
      case 'general':    return ['General Store'];
      case 'community':  return ['Community Check', 'Community Helpers'];
      default:           return ['Parts & Hardware', 'Repair & Services', 'Food & Catering', 'Express Rider', 'Rooms & Boarding', 'General Store', 'Community Check', 'Community Helpers'];
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    LocationService.currentLocationNotifier.addListener(_onLocationChanged);
    _loadShops();
    _updateLocation();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    LocationService.currentLocationNotifier.removeListener(_onLocationChanged);
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
        _currentPosition = Position(
          longitude: loc.longitude,
          latitude: loc.latitude,
          timestamp: loc.updatedAt,
          accuracy: 0,
          altitude: 0,
          altitudeAccuracy: 0,
          heading: 0,
          headingAccuracy: 0,
          speed: 0,
          speedAccuracy: 0,
        );
      });
    }
  }

  bool _isUpdatingLocation = false;

  Future<void> _updateLocation({bool forceRefresh = false}) async {
    if (mounted) setState(() => _isUpdatingLocation = true);
    try {
      final pos = await LocationService.getCurrentPosition(forceRefresh: forceRefresh);
      if (pos != null) {
        final locData = await LocationService.getCityAndBarangay(pos.latitude, pos.longitude);
        if (mounted) {
          setState(() {
            _currentPosition = pos;
            _currentCityName = locData['city'] ?? 'Current City';
          });
          if (forceRefresh) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('📍 Precise location updated: ${locData['barangay']}, ${locData['city']}'),
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

  Future<void> _loadShops() async {
    final userId = AuthService.currentUserId;
    debugPrint('[PingShops] currentUserId=$userId');
    if (userId == null) {
      if (mounted) setState(() => _profileLoaded = true);
      return;
    }

    try {
      final data = await Supabase.instance.client
          .from('responders')
          .select()
          .eq('profile_id', userId)
          .order('created_at', ascending: true)
          .timeout(const Duration(seconds: 15));

      final shops = List<Map<String, dynamic>>.from(data);
      debugPrint('[PingShops] loaded ${shops.length} shops, '
          'types=${shops.map((s) => s['responder_type']).toList()}');

      // Try to restore the last active shop from SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final activeId = prefs.getString('active_shop_id');
      int activeIdx = 0;
      if (activeId != null) {
        final found = shops.indexWhere((s) => s['id'] == activeId);
        if (found >= 0) activeIdx = found;
      }

      if (mounted) {
        setState(() {
          _shops = shops;
          _activeShopIndex = activeIdx;
          _profileLoaded = true;
        });

        if (shops.isEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _addNewShop());
        } else {
          // Silently keep the active shop's GPS fresh so the requester
          // nearby indicator stays accurate.
          _refreshActiveShopLocation(shops[activeIdx]);
        }
      }
    } catch (e) {
      debugPrint('[PingShops] LOAD ERROR: $e');
      if (mounted) setState(() => _profileLoaded = true);
    }
  }

  /// Silently patches the shop's lat/lng in Supabase with the current device GPS.
  Future<void> _refreshActiveShopLocation(Map<String, dynamic> shop) async {
    final loc = LocationService.currentLocationNotifier.value;
    if (loc == null) return;
    final shopId = shop['id'];
    if (shopId == null) return;
    try {
      await Supabase.instance.client.from('responders').update({
        'latitude':  loc.latitude,
        'longitude': loc.longitude,
        'city_name': loc.city,
      }).eq('id', shopId);
      debugPrint('[PingShops] GPS refreshed for shop $shopId');
    } catch (e) {
      debugPrint('[PingShops] GPS refresh error: $e');
    }
  }

  Future<void> _addNewShop() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ResponderRegistrationScreen()),
    );
    if (result == true) _loadShops();
  }

  Future<void> _editShop(Map<String, dynamic> shop) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ResponderRegistrationScreen(existingShop: shop),
      ),
    );
    if (result == true) _loadShops();
  }

  Future<void> _switchShop(int index) async {
    final shop = _shops[index];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_shop_id',      shop['id']);
    await prefs.setString('responder_shop_name', shop['shop_name'] ?? '');
    await prefs.setString('responder_type',      shop['responder_type'] ?? '');
    setState(() {
      _activeShopIndex = index;
      _showAll = false;
    });
  }

  String _typeEmoji(String? type) {
    switch (type) {
      case 'auto_parts': return '\ud83d\ude97';
      case 'hardware':   return '\ud83d\udd27';
      case 'rooms':      return '\ud83c\udfe0';
      case 'rider':      return '\ud83d\udce6';
      case 'food':       return '\ud83c\udf7d\ufe0f';
      case 'repair':     return '\ud83d\udee0\ufe0f';
      case 'community':  return '\ud83d\udccd';
      default:           return '\ud83c\udfea';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_profileLoaded) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Color(0xFF004D40))),
      );
    }

    final activeShop = _activeShop;
    final String userEmail = AuthService.currentUser?.email ?? '';
    final String userInitial = userEmail.isNotEmpty ? userEmail[0].toUpperCase() : 'M';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      drawer: AppDrawer(
        isMerchantMode: true,
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
        title: Row(
          children: [
            ShaderMask(
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
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: const Text(
                'MERCHANT',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: Color(0xFFD97706), letterSpacing: 0.5),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _addNewShop,
            icon: const Icon(Icons.add_business_outlined, color: Color(0xFF004D40)),
            tooltip: 'Add Another Shop',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFE2E8F0), height: 1),
        ),
      ),
      body: IndexedStack(
        index: _tabIndex,
        children: [
          // ── Tab 0: Live Requests ─────────────────────────────────────
          Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // -- Header ------------------------------------------------------
          Container(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    width: 8, height: 8,
                    decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  const Text('Live Pings',
                      style: TextStyle(color: Color(0xFF0F172A), fontSize: 20, fontWeight: FontWeight.w900)),
                ]),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Customer Pings Near $_currentCityName',
                        style: const TextStyle(color: Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: _isUpdatingLocation ? null : () => _updateLocation(forceRefresh: true),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: _isUpdatingLocation
                            ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF004D40)))
                            : const Icon(Icons.refresh_rounded, size: 14, color: Color(0xFF004D40)),
                      ),
                    ),
                  ],
                ),

                if (_shops.isNotEmpty) ...[
                  const SizedBox(height: 12),

                  // -- Shop Switcher ----------------------------------------
                  const Text('Active Shop', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF94A3B8), letterSpacing: 0.5)),
                  const SizedBox(height: 6),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ..._shops.asMap().entries.map((entry) {
                          final i = entry.key;
                          final shop = entry.value;
                          final isActive = i == _activeShopIndex;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: GestureDetector(
                              onTap: () => _switchShop(i),
                              onLongPress: () => _editShop(shop),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isActive ? const Color(0xFF004D40) : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isActive ? const Color(0xFF004D40) : const Color(0xFFE2E8F0),
                                    width: isActive ? 2 : 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(_typeEmoji(shop['responder_type']), style: const TextStyle(fontSize: 13)),
                                    const SizedBox(width: 6),
                                    Text(
                                      shop['shop_name'] ?? 'Shop',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: isActive ? Colors.white : const Color(0xFF334155),
                                      ),
                                    ),
                                    if (isActive) ...[
                                      const SizedBox(width: 4),
                                      const Icon(Icons.edit_outlined, size: 11, color: Colors.white60),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // -- Request Feed -------------------------------------------------
          Expanded(
            child: _LiveRequestsFeed(
              matchingCategories: _matchingCategories(),
              showAll: _showAll,
              onShowAllChanged: (v) => setState(() => _showAll = v),
              shopName: activeShop?['shop_name'] ?? 'Unknown Shop',
              currentPosition: _currentPosition,
            ),
          ),
        ],
      ),
          // ── Tab 1: My Offers ───────────────────────────────────────
          const MyOffersScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        height: 68,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 20, offset: const Offset(0, -5)),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Left: Notifications Bell
            const NotificationBell(),

            // Center: Tab Switcher Pill (Live Pings vs My Offers)
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () => setState(() => _tabIndex = 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: _tabIndex == 0 ? const Color(0xFF004D40) : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.dynamic_feed, size: 16, color: _tabIndex == 0 ? Colors.white : const Color(0xFF64748B)),
                          const SizedBox(width: 6),
                          Text(
                            'Live Pings',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _tabIndex == 0 ? Colors.white : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _tabIndex = 1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: _tabIndex == 1 ? const Color(0xFF004D40) : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.local_offer, size: 16, color: _tabIndex == 1 ? Colors.white : const Color(0xFF64748B)),
                          const SizedBox(width: 6),
                          Text(
                            'My Offers',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _tabIndex == 1 ? Colors.white : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Right: My Account Avatar
            GestureDetector(
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountCenterScreen(isMerchantMode: true)));
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
                    userInitial,
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

/// Live feed of customer Pings for the merchant.
///
/// The list is loaded with a plain query first so it renders even when the
/// Realtime channel for `requests` is unavailable; the stream is then attached
/// on top for live updates rather than being the only source of data.
class _LiveRequestsFeed extends StatefulWidget {
  final List<String> matchingCategories;
  final bool showAll;
  final ValueChanged<bool> onShowAllChanged;
  final String shopName;
  final Position? currentPosition;

  const _LiveRequestsFeed({
    required this.matchingCategories,
    required this.showAll,
    required this.onShowAllChanged,
    required this.shopName,
    this.currentPosition,
  });

  @override
  State<_LiveRequestsFeed> createState() => _LiveRequestsFeedState();
}

class _LiveRequestsFeedState extends State<_LiveRequestsFeed> {
  static const _visibleStatuses = {'open', 'active', 'matched'};

  List<Map<String, dynamic>> _requests = [];
  Set<String> _offeredRequestIds = {};
  StreamSubscription<List<Map<String, dynamic>>>? _liveSub;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _liveSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _error = null);
    try {
      final userId = AuthService.currentUserId;

      // Fetch requests and my existing offers in parallel
      final results = await Future.wait([
        Supabase.instance.client
            .from('requests')
            .select()
            .order('created_at', ascending: false)
            .timeout(const Duration(seconds: 15)),
        if (userId != null)
          Supabase.instance.client
              .from('offers')
              .select('request_id')
              .eq('user_id', userId)
              .timeout(const Duration(seconds: 10))
        else
          Future.value(<dynamic>[]),
      ]);

      final data = results[0] as List<dynamic>;
      final myOffers = results[1] as List<dynamic>;
      final offeredIds = myOffers
          .map((o) => (o as Map)['request_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();

      debugPrint('[PingFeed] fetched ${data.length} rows from requests');
      debugPrint('[PingFeed] already offered on ${offeredIds.length} pings');

      if (!mounted) return;
      setState(() {
        _requests = _visibleOnly(data);
        _offeredRequestIds = offeredIds;
        _loading = false;
      });
      _listenForLiveUpdates();
    } catch (e) {
      debugPrint('[PingFeed] FETCH ERROR: $e');
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  /// Realtime is additive: if the channel never delivers, the fetched feed
  /// stays on screen instead of the view hanging on a spinner.
  void _listenForLiveUpdates() {
    _liveSub?.cancel();
    _liveSub = Supabase.instance.client
        .from('requests')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .listen(
          (rows) {
            if (mounted) setState(() => _requests = _visibleOnly(rows));
          },
          onError: (_) {},
        );
  }

  List<Map<String, dynamic>> _visibleOnly(List<dynamic> rows) => rows
      .cast<Map<String, dynamic>>()
      .where((r) {
        final st = (r['status'] ?? 'open').toString().trim().toLowerCase();
        return _visibleStatuses.contains(st) || st == 'pending' || st == 'new';
      })
      .toList();

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF004D40)));
    }

    if (_error != null) {
      return ListView(children: [
        const SizedBox(height: 60),
        Center(
          child: Column(children: [
            const Icon(Icons.cloud_off_rounded, size: 40, color: Color(0xFF94A3B8)),
            const SizedBox(height: 12),
            const Text('Could not load Pings.',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(_error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF004D40),
                foregroundColor: Colors.white,
                minimumSize: const Size(120, 40),
              ),
            ),
          ]),
        ),
      ]);
    }

    final matchingCats = widget.matchingCategories;
    final allActive = List<Map<String, dynamic>>.from(_requests);

    final matchingRequests = allActive.where((r) {
      return matchingCats.isEmpty || matchingCats.contains(r['category'] ?? '');
    }).toList();

    final outsideRequests = allActive.where((r) {
      return matchingCats.isNotEmpty && !matchingCats.contains(r['category'] ?? '');
    }).toList();

    // Never strand the merchant on a blank list: if nothing matches their shop
    // category but Pings do exist, show everything instead of rendering zero
    // rows. Reachable with legacy categories such as 'Community Updates', which
    // no _matchingCategories() branch lists.
    final autoFellBack = matchingRequests.isEmpty && allActive.isNotEmpty;

    // When showing all, place category-matched requests first
    final requests = (widget.showAll || autoFellBack)
        ? [...matchingRequests, ...outsideRequests]
        : matchingRequests;
    final outsideCount = outsideRequests.length;

    debugPrint('[PingFeed] shopCats=$matchingCats totalActive=${allActive.length} '
        'matching=${matchingRequests.length} outside=$outsideCount rendering=${requests.length}');

    if (allActive.isEmpty) {
      return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 80),
            Center(
              child: Column(
                children: [
                  Icon(Icons.radar_rounded, size: 48, color: Color(0xFFCBD5E1)),
                  SizedBox(height: 12),
                  Text('No active customer Pings right now',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                  SizedBox(height: 6),
                  Text('When customers broadcast a request, it will appear here live.',
                      style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                ],
              ),
            ),
          ],
      );
    }

    return Container(
      color: Colors.transparent,
      child: Column(
        children: [
          // Quick Filter Toggle Pill Bar
          if (matchingCats.isNotEmpty && allActive.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: const Color(0xFFF1F5F9),
              child: Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () => widget.onShowAllChanged(true),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: widget.showAll ? const Color(0xFF004D40) : Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: widget.showAll ? const Color(0xFF004D40) : const Color(0xFFCBD5E1),
                                ),
                              ),
                              child: Text(
                                'All Pings (${allActive.length})',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: widget.showAll ? Colors.white : const Color(0xFF475569),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => widget.onShowAllChanged(false),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: !widget.showAll ? const Color(0xFF004D40) : Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: !widget.showAll ? const Color(0xFF004D40) : const Color(0xFFCBD5E1),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    'Shop Category (${matchingRequests.length})',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: !widget.showAll ? Colors.white : const Color(0xFF475569),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

          if (autoFellBack)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, size: 15, color: Color(0xFFD97706)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No Pings match your shop category yet — showing all '
                      '${allActive.length} active Ping${allActive.length > 1 ? 's' : ''}.',
                      style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFB45309)),
                    ),
                  ),
                ],
              ),
            ),

          Expanded(
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: requests.length,
              itemBuilder: (context, index) {
                final req = requests[index];
                return _RequestCard(
                  request: req,
                  shopName: widget.shopName,
                  currentPosition: widget.currentPosition,
                  dimmed: !autoFellBack && widget.showAll && matchingCats.isNotEmpty &&
                          !matchingCats.contains(req['category'] ?? ''),
                  alreadyOffered: _offeredRequestIds.contains(req['id']?.toString()),
                  onOfferSent: (requestId) {
                    setState(() => _offeredRequestIds.add(requestId));
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  final Map<String, dynamic> request;
  final String shopName;
  final Position? currentPosition;
  final bool dimmed;
  final bool alreadyOffered;
  final void Function(String requestId)? onOfferSent;

  const _RequestCard({
    required this.request,
    required this.shopName,
    this.currentPosition,
    this.dimmed = false,
    this.alreadyOffered = false,
    this.onOfferSent,
  });

  String _fulfillmentLabel(String type) {
    switch (type) {
      case 'delivery': return '🛵 Express Delivery';
      case 'pickup':   return '🛍️ Reserve for Pickup';
      case 'visit':    return '🔧 Schedule Site Visit';
      case 'reserve':  return '📅 Inquire / Reserve';
      case 'status':   return '📸 Live Photo / Status';
      default:         return '✨ $type';
    }
  }

  @override
  Widget build(BuildContext context) {
    final category    = request['category'] ?? 'General';
    final subCategory = request['sub_category'] ?? '';
    final description = request['description'] ?? '';
    final maxBudget   = (request['max_budget'] ?? 0).toDouble();
    final status      = request['status'] ?? 'active';
    final fulfillment = request['fulfillment_type'] ?? 'pickup';
    final isMatched   = status == 'matched';

    Map<String, dynamic> tags = {};
    try {
      final raw = request['tags'];
      if (raw is String && raw.isNotEmpty) tags = jsonDecode(raw);
      else if (raw is Map) tags = Map<String, dynamic>.from(raw);
    } catch (_) {}

    final vehicleModel    = tags['vehicle_model'] ?? tags['spec_1'] ?? '';
    final partSpec        = tags['part_spec'] ?? tags['spec_2'] ?? '';
    final airconPreferred = tags['aircon_preferred'] == true;

    String distanceLabel = '📍 Nearby';
    if (currentPosition != null && tags['lat'] != null && tags['lng'] != null) {
      try {
        final reqLat = (tags['lat'] as num).toDouble();
        final reqLng = (tags['lng'] as num).toDouble();
        final dist = LocationService.calculateDistanceString(
          currentPosition!.latitude,
          currentPosition!.longitude,
          reqLat,
          reqLng,
        );
        distanceLabel = '📍 $dist away';
      } catch (_) {}
    }

    String emoji = '📌';
    if (category.contains('Parts'))     emoji = '🚗';
    if (category.contains('Rider'))     emoji = '📦';
    if (category.contains('Rooms'))     emoji = '🏠';
    if (category.contains('Community')) emoji = '📍';

    final cardColor   = isMatched      ? const Color(0xFFECFDF5)
                      : alreadyOffered ? const Color(0xFFF0FDF4)
                      : Colors.white;
    final borderColor = isMatched      ? const Color(0xFFD1FAE5)
                      : alreadyOffered ? const Color(0xFF86EFAC)
                      : const Color(0xFFE2E8F0);
    final borderWidth = (isMatched || alreadyOffered) ? 1.5 : 1.0;

    return Opacity(
      opacity: dimmed ? 0.55 : 1.0,
      child: Card(
        margin: const EdgeInsets.only(bottom: 14),
        elevation: 0,
        color: cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: borderColor, width: borderWidth),
        ),
        child: InkWell(
          onTap: () async {
            if (isMatched) {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => OrderSummarySheet(request: request),
              );
            } else {
              final sent = await showModalBottomSheet<bool>(
                context: context,
                isScrollControlled: true,
                builder: (_) => OfferBottomSheet(
                  requestId: request['id'],
                  request: request,
                  shopName: shopName,
                ),
              );
              if (sent == true && request['id'] != null) {
                onOfferSent?.call(request['id'].toString());
              }
            }
          },
          borderRadius: BorderRadius.circular(24),
            child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Row: Category chip (Left) + Distance chip (Right)
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: alreadyOffered
                              ? const Color(0xFFDCFCE7)
                              : isMatched
                                  ? const Color(0xFFDCFCE7)
                                  : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(50),
                        ),
                        child: Text(
                          '$emoji  $category  ·  ${_fulfillmentLabel(fulfillment)}',
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: (alreadyOffered || isMatched)
                                ? const Color(0xFF15803D)
                                : const Color(0xFF475569),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.near_me_rounded, size: 11, color: Color(0xFF004D40)),
                          const SizedBox(width: 4),
                          Text(
                            distanceLabel.replaceAll('📍 ', ''),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF004D40),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                if (subCategory.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: Text(
                      subCategory,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFB45309),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 12),

                // Item Title / Description
                Text(
                  description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF0F172A),
                    height: 1.3,
                  ),
                ),

                // Grouped Specifications Box (Vehicle, Spec, Aircon)
                if (vehicleModel.isNotEmpty || partSpec.isNotEmpty || airconPreferred) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (vehicleModel.isNotEmpty)
                          _SpecChip(icon: Icons.directions_car_rounded, label: vehicleModel, iconColor: const Color(0xFF2563EB), textColor: const Color(0xFF1E40AF)),
                        if (partSpec.isNotEmpty)
                          _SpecChip(icon: Icons.build_rounded, label: partSpec, iconColor: const Color(0xFFEA580C), textColor: const Color(0xFFC2410C)),
                        if (airconPreferred)
                          const _SpecChip(icon: Icons.ac_unit_rounded, label: 'Aircon Preferred', iconColor: Color(0xFF0EA5E9), textColor: Color(0xFF0284C7)),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 16),
                const Divider(color: Color(0xFFEFF2F6), height: 1),
                const SizedBox(height: 16),

                // Footer: Budget + Action Button
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Budget block
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            category == 'Community Check' ? 'SPOTTER TIP' : 'MAX BUDGET',
                            style: GoogleFonts.outfit(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF94A3B8),
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatAccountingCurrency(maxBudget),
                            style: GoogleFonts.outfit(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF004D40),
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 12),

                    // ── Action Button ──────────────────────────
                    if (isMatched)
                      _StatusButton(
                        label: 'Accepted',
                        icon: Icons.verified_rounded,
                        bg: const Color(0xFF10B981),
                        fg: Colors.white,
                      )
                    else if (alreadyOffered)
                      GestureDetector(
                        onTap: () async {
                          final sent = await showModalBottomSheet<bool>(
                            context: context,
                            isScrollControlled: true,
                            builder: (_) => OfferBottomSheet(
                              requestId: request['id'],
                              request: request,
                              shopName: shopName,
                            ),
                          );
                          if (sent == true && request['id'] != null) {
                            onOfferSent?.call(request['id'].toString());
                          }
                        },
                        child: _StatusButton(
                          label: 'Offer Sent',
                          icon: Icons.check_rounded,
                          bg: const Color(0xFFDCFCE7),
                          fg: const Color(0xFF15803D),
                          trailingIcon: Icons.arrow_forward_ios_rounded,
                          trailingIconSize: 10,
                        ),
                      )
                    else
                      GestureDetector(
                        onTap: () async {
                          final sent = await showModalBottomSheet<bool>(
                            context: context,
                            isScrollControlled: true,
                            builder: (_) => OfferBottomSheet(
                              requestId: request['id'],
                              request: request,
                              shopName: shopName,
                            ),
                          );
                          if (sent == true && request['id'] != null) {
                            onOfferSent?.call(request['id'].toString());
                          }
                        },
                        child: _StatusButton(
                          label: 'Send Offer',
                          icon: Icons.send_rounded,
                          bg: const Color(0xFF004D40),
                          fg: Colors.white,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color bg;
  final Color fg;
  final IconData? trailingIcon;
  final double trailingIconSize;
  const _StatusButton({
    required this.label,
    required this.icon,
    required this.bg,
    required this.fg,
    this.trailingIcon,
    this.trailingIconSize = 12,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(50),
        boxShadow: bg == const Color(0xFF004D40)
            ? [BoxShadow(color: const Color(0xFF004D40).withValues(alpha: 0.25), blurRadius: 14, offset: const Offset(0, 5))]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 8),
          Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: fg,
            ),
          ),
          if (trailingIcon != null) ...[
            const SizedBox(width: 6),
            Icon(trailingIcon, size: trailingIconSize, color: fg.withValues(alpha: 0.6)),
          ],
        ],
      ),
    );
  }
}

class _SpecChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color iconColor;
  final Color textColor;
  const _SpecChip({
    required this.icon,
    required this.label,
    required this.iconColor,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(50),
        border: Border.all(color: iconColor.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: iconColor),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: textColor)),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  final Color? border;
  const _Badge({required this.label, required this.bg, required this.fg, this.border});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(50),
        border: border != null ? Border.all(color: border!) : null,
      ),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
    );
  }
}

String _formatAccountingCurrency(num amount) {
  final parts = amount.toStringAsFixed(2).split('.');
  final integerPart = parts[0];
  final decimalPart = parts[1];
  final regExp = RegExp(r'(\d+?)(?=(\d{3})+(?!\d))');
  final formattedInteger = integerPart.replaceAllMapped(regExp, (Match m) => '${m[1]},');
  return '₱$formattedInteger.$decimalPart';
}

