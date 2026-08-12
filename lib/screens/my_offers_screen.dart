import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../utils/transaction_number.dart';
import '../widgets/order_summary_sheet.dart';

// One row's worth of pre-computed display state — built once per offer so
// filtering by status doesn't re-derive it, and so the card and the filter
// tabs always agree on what "status" means for a given offer.
class _OfferEntry {
  final Map<String, dynamic> offer;
  final Map<String, dynamic>? request;
  final String statusKey;
  final String statusLabel;
  final Color statusColor;
  final Color statusBg;
  final IconData statusIcon;
  final bool reqMatched;
  final bool isMyOfferWon;
  final String orderStage;

  _OfferEntry({
    required this.offer,
    required this.request,
    required this.statusKey,
    required this.statusLabel,
    required this.statusColor,
    required this.statusBg,
    required this.statusIcon,
    required this.reqMatched,
    required this.isMyOfferWon,
    required this.orderStage,
  });
}

class MyOffersScreen extends StatefulWidget {
  const MyOffersScreen({super.key});

  @override
  State<MyOffersScreen> createState() => _MyOffersScreenState();
}

class _MyOffersScreenState extends State<MyOffersScreen> {
  String _filter = 'active'; // 'active' | 'history'

  // Offers still moving toward an outcome vs. offers that are settled —
  // this is what actually determines which tab an offer lands in.
  static const _activeStatusKeys = {'pending', 'accepted', 'ready'};

  // Memoized by which offers are actually loaded, not recreated every
  // build — otherwise switching tabs (a pure `setState` on `_filter`, no
  // new data) re-triggers the request fetch, and while it's in flight the
  // request lookup is empty, so every offer falls back to its default
  // status and briefly shows in the wrong tab.
  Future<List<Map<String, dynamic>>>? _requestsFuture;
  String? _requestsFutureKey;

  Future<List<Map<String, dynamic>>> _requestsFor(List<Map<String, dynamic>> offers) {
    final ids = offers
        .map((o) => o['request_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final key = ids.join(',');
    if (_requestsFutureKey != key) {
      _requestsFutureKey = key;
      _requestsFuture = _loadRequestsForOffers(offers);
    }
    return _requestsFuture!;
  }

  String _timeAgo(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt.toLocal());
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String _categoryEmoji(String category) {
    switch (category) {
      case 'Parts & Hardware':  return '🚗';
      case 'Express Rider':     return '📦';
      case 'Rooms & Boarding':  return '🏠';
      case 'Food & Catering':   return '🍽️';
      case 'Repair & Services': return '🛠️';
      case 'General Store':     return '🏪';
      case 'Community Check':   return '📍';
      case 'Community Helpers': return '🚨';
      default:                  return '📌';
    }
  }

  _OfferEntry _buildEntry(Map<String, dynamic> offer, Map<String, dynamic>? request) {
    final reqStatus     = request?['status'] ?? 'active';
    final acceptedOffer = request?['accepted_offer_id'];
    final isMyOfferWon  = acceptedOffer == offer['id'];
    final reqMatched    = reqStatus == 'matched';

    Map<String, dynamic> reqTags = {};
    final rawTags = request?['tags'];
    if (rawTags is String && rawTags.isNotEmpty) {
      try {
        reqTags = Map<String, dynamic>.from(jsonDecode(rawTags));
      } catch (_) {}
    } else if (rawTags is Map) {
      reqTags = Map<String, dynamic>.from(rawTags);
    }
    final orderStage = (reqTags['order_stage'] ?? 'matched').toString();

    // Six distinct hues so states can't blur into each other during a scan —
    // in particular Pending vs Ready (both used to be amber/orange) and Not
    // Selected vs Closed (both used to be near-identical gray).
    String statusKey;
    String statusLabel;
    Color statusColor;
    Color statusBg;
    IconData statusIcon;

    if (reqMatched && isMyOfferWon && orderStage == 'completed') {
      statusKey   = 'completed';
      statusLabel = 'Completed';
      statusColor = const Color(0xFF15803D);
      statusBg    = const Color(0xFFDCFCE7);
      statusIcon  = Icons.verified_rounded;
    } else if (reqMatched && isMyOfferWon && orderStage == 'ready') {
      statusKey   = 'ready';
      statusLabel = 'Ready';
      statusColor = const Color(0xFFB45309);
      statusBg    = const Color(0xFFFFF7ED);
      statusIcon  = Icons.local_shipping_rounded;
    } else if (reqMatched && isMyOfferWon) {
      statusKey   = 'accepted';
      statusLabel = 'Accepted';
      statusColor = const Color(0xFF2563EB);
      statusBg    = const Color(0xFFEFF6FF);
      statusIcon  = Icons.handshake_rounded;
    } else if (reqMatched && !isMyOfferWon) {
      statusKey   = 'not_selected';
      statusLabel = 'Not Selected';
      statusColor = const Color(0xFF64748B);
      statusBg    = const Color(0xFFF1F5F9);
      statusIcon  = Icons.cancel_outlined;
    } else if (reqStatus == 'active' || reqStatus == 'open') {
      statusKey   = 'pending';
      statusLabel = 'Pending';
      statusColor = const Color(0xFF7C3AED);
      statusBg    = const Color(0xFFF3E8FF);
      statusIcon  = Icons.access_time_rounded;
    } else {
      statusKey   = 'closed';
      statusLabel = 'Closed';
      statusColor = const Color(0xFF991B1B);
      statusBg    = const Color(0xFFFEF2F2);
      statusIcon  = Icons.block_rounded;
    }

    return _OfferEntry(
      offer: offer,
      request: request,
      statusKey: statusKey,
      statusLabel: statusLabel,
      statusColor: statusColor,
      statusBg: statusBg,
      statusIcon: statusIcon,
      reqMatched: reqMatched,
      isMyOfferWon: isMyOfferWon,
      orderStage: orderStage,
    );
  }

  @override
  Widget build(BuildContext context) {
    final userId = AuthService.currentUserId;

    if (userId == null) {
      return const Center(child: Text('Not logged in.'));
    }

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('offers')
          .stream(primaryKey: ['id'])
          .eq('user_id', userId)
          .order('created_at', ascending: false),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF004D40)));
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final offers = snapshot.data ?? [];

        if (offers.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: const Icon(Icons.local_offer_outlined, size: 48, color: Color(0xFF94A3B8)),
                ),
                const SizedBox(height: 16),
                Text('No offers sent yet',
                    style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A))),
                const SizedBox(height: 6),
                Text('Offers you send will appear here\nwith their acceptance status.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(fontSize: 13, color: const Color(0xFF64748B))),
              ],
            ),
          );
        }

        return FutureBuilder<List<Map<String, dynamic>>>(
          future: _requestsFor(offers),
          builder: (context, reqSnapshot) {
            final requestsMap = <String, Map<String, dynamic>>{};
            if (reqSnapshot.hasData) {
              for (final r in reqSnapshot.data!) {
                requestsMap[r['id']] = r;
              }
            }

            final entries = offers
                .map((offer) => _buildEntry(offer, requestsMap[offer['request_id']]))
                .toList();
            final activeEntries  = entries.where((e) => _activeStatusKeys.contains(e.statusKey)).toList();
            final historyEntries = entries.where((e) => !_activeStatusKeys.contains(e.statusKey)).toList();
            final shown = _filter == 'active' ? activeEntries : historyEntries;

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Row(
                    children: [
                      _OfferFilterTab(
                        label: 'Active',
                        count: activeEntries.length,
                        selected: _filter == 'active',
                        onTap: () => setState(() => _filter = 'active'),
                      ),
                      const SizedBox(width: 8),
                      _OfferFilterTab(
                        label: 'History',
                        count: historyEntries.length,
                        selected: _filter == 'history',
                        onTap: () => setState(() => _filter = 'history'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: shown.isEmpty
                      ? Center(
                          child: Text(
                            _filter == 'active'
                                ? 'No offers awaiting a response right now.'
                                : 'Completed and closed offers will show up here.',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.plusJakartaSans(fontSize: 13, color: const Color(0xFF64748B)),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                          itemCount: shown.length,
                          itemBuilder: (context, index) => _OfferCard(
                            entry: shown[index],
                            categoryEmoji: _categoryEmoji,
                            timeAgo: _timeAgo,
                          ),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _loadRequestsForOffers(
      List<Map<String, dynamic>> offers) async {
    final ids = offers
        .map((o) => o['request_id'])
        .where((id) => id != null)
        .toSet()
        .toList();
    if (ids.isEmpty) return [];
    final data = await Supabase.instance.client
        .from('requests')
        .select('id, user_id, description, category, fulfillment_type, status, accepted_offer_id, tags')
        .inFilter('id', ids);
    return List<Map<String, dynamic>>.from(data);
  }
}

class _OfferFilterTab extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _OfferFilterTab({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF004D40) : Colors.white,
          borderRadius: BorderRadius.circular(50),
          border: Border.all(
            color: selected ? const Color(0xFF004D40) : const Color(0xFFE2E8F0),
          ),
          boxShadow: selected
              ? [BoxShadow(color: const Color(0xFF004D40).withValues(alpha: 0.18), blurRadius: 8, offset: const Offset(0, 3))]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : const Color(0xFF64748B),
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: selected ? Colors.white.withValues(alpha: 0.25) : const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: selected ? Colors.white : const Color(0xFF64748B),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  final _OfferEntry entry;
  final String Function(String) categoryEmoji;
  final String Function(String?) timeAgo;

  const _OfferCard({
    required this.entry,
    required this.categoryEmoji,
    required this.timeAgo,
  });

  @override
  Widget build(BuildContext context) {
    final offer   = entry.offer;
    final request = entry.request;

    final price      = (offer['offered_price'] ?? 0).toDouble();
    final note       = offer['note'] ?? '';
    final sellerName = (offer['seller_name'] ?? '').toString();
    final timeAgoStr = timeAgo(offer['created_at']);
    final reqDesc    = request?['description'] ?? 'Request';
    final category   = (request?['category'] ?? '').toString();
    final catEmoji   = categoryEmoji(category);

    final isTappable = entry.reqMatched && entry.isMyOfferWon && request != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: entry.reqMatched && entry.isMyOfferWon ? const Color(0xFFD1FAE5) : const Color(0xFFE2E8F0),
          width: entry.reqMatched && entry.isMyOfferWon ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isTappable
              ? () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => OrderSummarySheet(request: request!),
                  )
              : null,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        '$catEmoji  $reqDesc',
                        style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: entry.statusBg, borderRadius: BorderRadius.circular(50)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(entry.statusIcon, size: 12, color: entry.statusColor),
                        const SizedBox(width: 4),
                        Text(entry.statusLabel,
                            style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w800, color: entry.statusColor)),
                      ]),
                    ),
                  ],
                ),

                // Which shop this offer was sent from — a merchant running
                // more than one shop otherwise has no way to tell them apart
                // in this list.
                if (sellerName.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.storefront_rounded, size: 12, color: Color(0xFF94A3B8)),
                      const SizedBox(width: 4),
                      Text(sellerName,
                          style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w700, color: const Color(0xFF64748B))),
                    ],
                  ),
                ],

                const SizedBox(height: 14),
                const Divider(color: Color(0xFFEFF2F6), height: 1),
                const SizedBox(height: 14),

                // Price + time
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('YOUR OFFER',
                          style: GoogleFonts.plusJakartaSans(fontSize: 10, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w700, letterSpacing: 0.6)),
                      const SizedBox(height: 2),
                      Text(
                        _formatAccountingCurrency(price),
                        style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w900, color: const Color(0xFF004D40), letterSpacing: -0.3),
                      ),
                    ]),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.schedule_rounded, size: 12, color: Color(0xFFCBD5E1)),
                            const SizedBox(width: 4),
                            Text(timeAgoStr, style: GoogleFonts.plusJakartaSans(fontSize: 11, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w500)),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          transactionNumber(offer['request_id']),
                          style: const TextStyle(fontSize: 10, color: Color(0xFFCBD5E1), fontWeight: FontWeight.w700, letterSpacing: 0.2),
                        ),
                      ],
                    ),
                  ],
                ),

                // Note
                if (note.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(note, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: const Color(0xFF475569), height: 1.4)),
                  ),
                ],

                // Accepted/Ready/Completed banner — reuses the exact same
                // color and icon as the status pill above instead of its
                // own separate emoji-based palette, so the two can't disagree.
                if (entry.reqMatched && entry.isMyOfferWon) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: entry.statusBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: entry.statusColor.withValues(alpha: 0.35)),
                    ),
                    child: Row(children: [
                      Icon(entry.statusIcon, size: 16, color: entry.statusColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          entry.orderStage == 'completed'
                              ? 'Transaction completed. Tap to view summary.'
                              : entry.orderStage == 'ready'
                                  ? 'Marked ready — waiting for customer to confirm.'
                                  : 'Customer accepted your offer! Tap to coordinate & mark ready.',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: entry.statusColor,
                          ),
                        ),
                      ),
                    ]),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
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
