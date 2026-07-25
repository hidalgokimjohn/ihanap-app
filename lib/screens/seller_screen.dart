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
import 'account/account_center_screen.dart';
import 'package:google_fonts/google_fonts.dart';
import 'responder_registration_screen.dart';
import 'my_offers_screen.dart';

class SellerScreen extends StatefulWidget {
  const SellerScreen({super.key});

  @override
  State<SellerScreen> createState() => _SellerScreenState();
}

class _SellerScreenState extends State<SellerScreen> {
  String _currentCityName = 'Butuan City';
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
      case 'community':  return ['Community Updates'];
      case 'food':       return ['Parts & Hardware', 'Community Updates'];
      case 'repair':     return ['Parts & Hardware'];
      default:           return [];
    }
  }

  @override
  void initState() {
    super.initState();
    _loadShops();
    _loadLocation();
  }

  Future<void> _loadLocation() async {
    final pos = await LocationService.getCurrentPosition();
    if (pos != null) {
      final locData = await LocationService.getCityAndBarangay(pos.latitude, pos.longitude);
      if (mounted) {
        setState(() {
          _currentPosition = pos;
          _currentCityName = locData['city'] ?? 'Butuan City';
        });
      }
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('iHanap for Merchants',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        actions: [
          const NotificationBell(),
          // Add Shop button
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
                  const Text('Live Requests',
                      style: TextStyle(color: Color(0xFF0F172A), fontSize: 20, fontWeight: FontWeight.w900)),
                ]),
                const SizedBox(height: 2),
                Text(
                  'Customer Requests Near $_currentCityName',
                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 12, fontWeight: FontWeight.w500),
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

                  if (activeShop != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFBBF7D0)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(_typeEmoji(activeShop['responder_type']), style: const TextStyle(fontSize: 13)),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '${activeShop['shop_name']} • ${_typeLabel(activeShop['responder_type'])}  •  Tap chip to switch • Long-press to edit',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF059669)),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ]),
                    ),
                  ],
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

                final allRequests = snapshot.data ?? [];
                final matchingCats = _matchingCategories();

                final requests = allRequests.where((r) {
                  final statusOk = r['status'] == 'active' || r['status'] == 'matched';
                  if (!statusOk) return false;
                  if (_showAll || matchingCats.isEmpty) return true;
                  return matchingCats.contains(r['category'] ?? '');
                }).toList();

                final totalActive = allRequests.where((r) =>
                  r['status'] == 'active' || r['status'] == 'matched').length;
                final filteredOut = totalActive - requests.length;

                bool playedHaptic = false;
                Map<String, String> currentStatuses = {};
                for (var req in requests) {
                  final id = req['id'] as String;
                  final status = req['status'] as String;
                  currentStatuses[id] = status;
                  if (status == 'matched' && _previousStatuses[id] == 'active' && !playedHaptic) {
                    HapticFeedback.heavyImpact();
                    playedHaptic = true;
                  }
                }
                _previousStatuses = currentStatuses;

                if (requests.isEmpty) {
                  return ListView(children: [
                    const SizedBox(height: 60),
                    Center(
                      child: Column(children: [
                        const Text('No matching requests right now.',
                            style: TextStyle(fontSize: 16, color: Color(0xFF64748B))),
                        if (filteredOut > 0) ...[
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: () => setState(() => _showAll = true),
                            child: Text(
                              'Show $filteredOut other request${filteredOut > 1 ? 's' : ''} outside your category',
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
                  itemCount: requests.length + (filteredOut > 0 ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == requests.length) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 24),
                        child: GestureDetector(
                          onTap: () => setState(() => _showAll = !_showAll),
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
                                  _showAll ? Icons.filter_list_off : Icons.filter_list,
                                  size: 16,
                                  color: const Color(0xFF004D40),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _showAll
                                    ? 'Showing all requests • Tap to filter'
                                    : 'Show $filteredOut more request${filteredOut > 1 ? 's' : ''} outside your category',
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
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tabIndex,
        onTap: (i) => setState(() => _tabIndex = i),
        selectedItemColor: const Color(0xFF004D40),
        unselectedItemColor: const Color(0xFF94A3B8),
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        unselectedLabelStyle: const TextStyle(fontSize: 12),
        backgroundColor: Colors.white,
        elevation: 8,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dynamic_feed_outlined),
            activeIcon: Icon(Icons.dynamic_feed),
            label: 'Live Requests',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.local_offer_outlined),
            activeIcon: Icon(Icons.local_offer),
            label: 'My Offers',
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

    final vehicleModel    = tags['vehicle_model'] ?? '';
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
          onTap: isMatched
              ? () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => OrderSummarySheet(request: request),
                  )
              : null,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  _Badge(
                    label: '$emoji  $category',
                    bg: isMatched ? Colors.white : const Color(0xFFF8FAFC),
                    border: isMatched ? const Color(0xFFD1FAE5) : const Color(0xFFE2E8F0),
                    fg: const Color(0xFF334155),
                  ),
                  const Spacer(),
                  _Badge(label: distanceLabel, bg: const Color(0xFFE2F0F0), fg: const Color(0xFF004D40)),
                ]),

                if (subCategory.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFCBD5E1)),
                    ),
                    child: Text(subCategory,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF475569), fontWeight: FontWeight.w600)),
                  ),
                ],

                const SizedBox(height: 14),
                Text(description,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF0F172A), height: 1.4)),

                if (vehicleModel.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    const Icon(Icons.directions_car, size: 14, color: Color(0xFF64748B)),
                    const SizedBox(width: 6),
                    Text(vehicleModel, style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
                  ]),
                ],

                if (airconPreferred) ...[
                  const SizedBox(height: 8),
                  Row(children: const [
                    Icon(Icons.ac_unit, size: 14, color: Color(0xFF0EA5E9)),
                    SizedBox(width: 6),
                    Text('Aircon Preferred', style: TextStyle(fontSize: 13, color: Color(0xFF0EA5E9), fontWeight: FontWeight.w600)),
                  ]),
                ],

                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _fulfillmentBg(fulfillment),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_fulfillmentLabel(fulfillment),
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _fulfillmentFg(fulfillment))),
                ),

                const SizedBox(height: 16),
                const Divider(color: Color(0xFFE2E8F0), height: 1),
                const SizedBox(height: 16),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Max Budget',
                          style: TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
                      const SizedBox(height: 2),
                      Text('₱${maxBudget.toStringAsFixed(2)}',
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF004D40), letterSpacing: -0.5)),
                    ]),
                    if (isMatched)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                            color: const Color(0xFF10B981), borderRadius: BorderRadius.circular(20)),
                        child: const Row(children: [
                          Text('🎉 ', style: TextStyle(fontSize: 16)),
                          Text('Offer Accepted', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ]),
                      )
                    else
                      SizedBox(
                        width: 140,
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
                            backgroundColor: const Color(0xFF004D40),
                            foregroundColor: Colors.white,
                            minimumSize: const Size(0, 48),
                          ),
                          child: const Text('Send Offer', style: TextStyle(fontWeight: FontWeight.bold)),
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

