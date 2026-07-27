import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  Map<String, String> _previousStatuses = {};

  List<Map<String, dynamic>> _shops = [];
  int _activeShopIndex = 0;
  bool _profileLoaded = false;
  bool _showAll = false;
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
    if (userId == null) {
      if (mounted) setState(() => _profileLoaded = true);
      return;
    }

    try {
      final data = await Supabase.instance.client
          .from('responders')
          .select()
          .eq('profile_id', userId)
          .order('created_at', ascending: true);

      final shops = List<Map<String, dynamic>>.from(data);

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
        }
      }
    } catch (e) {
      if (mounted) setState(() => _profileLoaded = true);
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
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: Supabase.instance.client
                  .from('requests')
                  .stream(primaryKey: ['id'])
                  .order('created_at', ascending: false),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Color(0xFF004D40)));
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}', textAlign: TextAlign.center));
                }

                final allActive = (snapshot.data ?? []).where((r) {
                  final status = r['status'];
                  return status == 'open' || status == 'active' || status == 'matched';
                }).toList();

                final matchingCats = _matchingCategories();

                final matchingRequests = allActive.where((r) {
                  return matchingCats.isEmpty || matchingCats.contains(r['category'] ?? '');
                }).toList();

                final outsideCount = allActive.length - matchingRequests.length;
                final requests = _showAll ? allActive : matchingRequests;
                final showToggleBtn = matchingCats.isNotEmpty && outsideCount > 0;

                if (requests.isEmpty) {
                  return ListView(children: [
                    const SizedBox(height: 60),
                    Center(
                      child: Column(children: [
                        const Text('No matching Pings right now.',
                            style: TextStyle(fontSize: 16, color: Color(0xFF64748B))),
                        if (outsideCount > 0) ...[
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: () => setState(() => _showAll = true),
                            child: Text(
                              'Show $outsideCount other Ping${outsideCount > 1 ? 's' : ''} outside your category',
                              style: const TextStyle(fontSize: 13, color: Color(0xFF004D40),
                                  fontWeight: FontWeight.w600, decoration: TextDecoration.underline),
                            ),
                          ),
                        ],
                      ]),
                    ),
                  ]);
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: requests.length + (showToggleBtn ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == requests.length) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 24),
                        child: InkWell(
                          onTap: () => setState(() => _showAll = !_showAll),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _showAll ? Icons.filter_alt_off_rounded : Icons.filter_alt_rounded,
                                  size: 16,
                                  color: const Color(0xFF004D40),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _showAll
                                    ? 'Showing all requests • Tap to filter to your category'
                                    : 'Show $outsideCount more request${outsideCount > 1 ? 's' : ''} outside your category',
                                  style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF004D40)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }
                    return _RequestCard(
                      request: requests[index],
                      shopName: activeShop?['shop_name'] ?? 'Unknown Shop',
                      currentPosition: _currentPosition,
                      dimmed: _showAll && matchingCats.isNotEmpty &&
                              !matchingCats.contains(requests[index]['category'] ?? ''),
                    );
                  },
                );
              },
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

class _RequestCard extends StatelessWidget {
  final Map<String, dynamic> request;
  final String shopName;
  final Position? currentPosition;
  final bool dimmed;
  const _RequestCard({
    required this.request,
    required this.shopName,
    this.currentPosition,
    this.dimmed = false,
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

  Color _fulfillmentBg(String type) {
    switch (type) {
      case 'delivery': return const Color(0xFFFFF7ED);
      case 'pickup':   return const Color(0xFFEFF6FF);
      case 'visit':    return const Color(0xFFF5F3FF);
      case 'reserve':  return const Color(0xFFF0FDF4);
      case 'status':   return const Color(0xFFFDF4FF);
      default:         return const Color(0xFFF8FAFC);
    }
  }

  Color _fulfillmentFg(String type) {
    switch (type) {
      case 'delivery': return const Color(0xFFEA580C);
      case 'pickup':   return const Color(0xFF2563EB);
      case 'visit':    return const Color(0xFF7C3AED);
      case 'reserve':  return const Color(0xFF059669);
      case 'status':   return const Color(0xFF9333EA);
      default:         return const Color(0xFF64748B);
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

    String distanceLabel = '?? 1.2 km';
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

    final cardColor   = isMatched ? const Color(0xFFECFDF5) : Colors.white;
    final borderColor = isMatched ? const Color(0xFFD1FAE5) : const Color(0xFFE2E8F0);

    return Opacity(
      opacity: dimmed ? 0.6 : 1.0,
      child: Card(
        margin: const EdgeInsets.only(bottom: 16),
        color: cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: borderColor),
        ),
        child: InkWell(
          onTap: () {
            if (isMatched) {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => OrderSummarySheet(request: request),
              );
            } else {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => OfferBottomSheet(
                  requestId: request['id'],
                  request: request,
                  shopName: shopName,
                ),
              );
            }
          },
          borderRadius: BorderRadius.circular(20),
            child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Row: Category + Fulfillment Breadcrumb (Left) & Distance Badge (Right)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isMatched ? Colors.white : const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Text(
                            '$emoji $category • ${_fulfillmentLabel(fulfillment)}',
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF334155),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _Badge(label: distanceLabel, bg: const Color(0xFFE2F0F0), fg: const Color(0xFF004D40)),
                  ],
                ),

                if (subCategory.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: Text(
                      '🏷️ $subCategory',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFD97706)),
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
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: const Border(
                        left: BorderSide(color: Color(0xFF004D40), width: 3),
                      ),
                    ),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (vehicleModel.isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.directions_car_outlined, size: 13, color: Color(0xFF2563EB)),
                              const SizedBox(width: 4),
                              Text(vehicleModel, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF1E40AF))),
                            ],
                          ),
                        if (partSpec.isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.build_circle_outlined, size: 13, color: Color(0xFFEA580C)),
                              const SizedBox(width: 4),
                              Text(partSpec, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFC2410C))),
                            ],
                          ),
                        if (airconPreferred)
                          const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.ac_unit_rounded, size: 13, color: Color(0xFF0EA5E9)),
                              SizedBox(width: 4),
                              Text('Aircon Preferred', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF0284C7))),
                            ],
                          ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 14),
                const Divider(color: Color(0xFFE2E8F0), height: 1),
                const SizedBox(height: 14),

                // Footer Row: Budget Highlight + Send Offer Action Button
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          category == 'Community Check' ? 'SPOTTER TIP' : 'MAX BUDGET',
                          style: GoogleFonts.outfit(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF64748B),
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatAccountingCurrency(maxBudget),
                          style: GoogleFonts.outfit(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF004D40),
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                    if (isMatched)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Row(
                          children: [
                            Text('🎉 ', style: TextStyle(fontSize: 14)),
                            Text('Offer Accepted', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                          ],
                        ),
                      )
                    else
                      Container(
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF004D40), Color(0xFF00695C)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: const [
                            BoxShadow(color: Color(0x20004D40), blurRadius: 10, offset: Offset(0, 4)),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: () => showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            builder: (_) => OfferBottomSheet(
                              requestId: request['id'],
                              request: request,
                              shopName: shopName,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.bolt_rounded, size: 18, color: Color(0xFFFF8C42)),
                              const SizedBox(width: 6),
                              Text(
                                'Send Offer',
                                style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
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
        borderRadius: BorderRadius.circular(8),
        border: border != null ? Border.all(color: border!) : null,
      ),
      child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: fg)),
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

