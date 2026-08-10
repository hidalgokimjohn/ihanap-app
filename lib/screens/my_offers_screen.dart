import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../utils/transaction_number.dart';
import '../widgets/order_summary_sheet.dart';

class MyOffersScreen extends StatelessWidget {
  const MyOffersScreen({super.key});

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
          future: _loadRequestsForOffers(offers),
          builder: (context, reqSnapshot) {
            final requestsMap = <String, Map<String, dynamic>>{};
            if (reqSnapshot.hasData) {
              for (final r in reqSnapshot.data!) {
                requestsMap[r['id']] = r;
              }
            }

            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: offers.length,
              itemBuilder: (context, index) {
                final offer = offers[index];
                final request = requestsMap[offer['request_id']];

                final reqStatus      = request?['status'] ?? 'active';
                final acceptedOffer  = request?['accepted_offer_id'];
                final isMyOfferWon   = acceptedOffer == offer['id'];
                final reqMatched     = reqStatus == 'matched';

                Map<String, dynamic> reqTags = {};
                final rawTags = request?['tags'];
                if (rawTags is String && rawTags.isNotEmpty) {
                  try {
                    reqTags = Map<String, dynamic>.from(jsonDecode(rawTags));
                  } catch (_) {}
                } else if (rawTags is Map) {
                  reqTags = Map<String, dynamic>.from(rawTags);
                }
                final orderStage = reqTags['order_stage'] ?? 'matched';

                // Determine offer status
                String statusLabel;
                Color statusColor;
                Color statusBg;
                IconData statusIcon;

                if (reqMatched && isMyOfferWon && orderStage == 'completed') {
                  statusLabel = 'Completed';
                  statusColor = const Color(0xFF15803D);
                  statusBg    = const Color(0xFFDCFCE7);
                  statusIcon  = Icons.task_alt_rounded;
                } else if (reqMatched && isMyOfferWon && orderStage == 'ready') {
                  statusLabel = 'Ready';
                  statusColor = const Color(0xFFB45309);
                  statusBg    = const Color(0xFFFFF7ED);
                  statusIcon  = Icons.local_shipping_rounded;
                } else if (reqMatched && isMyOfferWon) {
                  statusLabel = 'Accepted';
                  statusColor = const Color(0xFF059669);
                  statusBg    = const Color(0xFFF0FDF4);
                  statusIcon  = Icons.check_circle_rounded;
                } else if (reqMatched && !isMyOfferWon) {
                  statusLabel = 'Not Selected';
                  statusColor = const Color(0xFF64748B);
                  statusBg    = const Color(0xFFF1F5F9);
                  statusIcon  = Icons.cancel_outlined;
                } else if (reqStatus == 'active' || reqStatus == 'open') {
                  statusLabel = 'Pending';
                  statusColor = const Color(0xFFD97706);
                  statusBg    = const Color(0xFFFFFBEB);
                  statusIcon  = Icons.access_time_rounded;
                } else {
                  statusLabel = 'Closed';
                  statusColor = const Color(0xFF94A3B8);
                  statusBg    = const Color(0xFFF8FAFC);
                  statusIcon  = Icons.block_rounded;
                }

                final price    = (offer['offered_price'] ?? 0).toDouble();
                final note     = offer['note'] ?? '';
                final timeAgo  = _timeAgo(offer['created_at']);
                final reqDesc  = request?['description'] ?? 'Request';
                final category = (request?['category'] ?? '').toString();
                final catEmoji = _categoryEmoji(category);

                final isTappable = reqMatched && isMyOfferWon && request != null;

                return Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: reqMatched && isMyOfferWon ? const Color(0xFFD1FAE5) : const Color(0xFFE2E8F0),
                      width: reqMatched && isMyOfferWon ? 1.5 : 1,
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
                                  decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(50)),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Icon(statusIcon, size: 12, color: statusColor),
                                    const SizedBox(width: 4),
                                    Text(statusLabel,
                                        style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w800, color: statusColor)),
                                  ]),
                                ),
                              ],
                            ),

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
                                    style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w900, color: const Color(0xFF004D40), letterSpacing: -0.5),
                                  ),
                                ]),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.schedule_rounded, size: 12, color: Color(0xFFCBD5E1)),
                                        const SizedBox(width: 4),
                                        Text(timeAgo, style: GoogleFonts.plusJakartaSans(fontSize: 11, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w500)),
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

                            // Accepted banner
                            if (reqMatched && isMyOfferWon) ...[
                              const SizedBox(height: 14),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: orderStage == 'completed' ? const Color(0xFFDCFCE7) : const Color(0xFFF0FDF4),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: orderStage == 'completed' ? const Color(0xFF86EFAC) : const Color(0xFFBBF7D0),
                                  ),
                                ),
                                child: Row(children: [
                                  Text(
                                    orderStage == 'completed' ? '✅ ' : orderStage == 'ready' ? '🚚 ' : '🎉 ',
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                  Expanded(
                                    child: Text(
                                      orderStage == 'completed'
                                          ? 'Transaction completed. Tap to view summary.'
                                          : orderStage == 'ready'
                                              ? 'Marked ready — waiting for customer to confirm.'
                                              : 'Customer accepted your offer! Tap to coordinate & mark ready.',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: orderStage == 'completed' ? const Color(0xFF15803D) : const Color(0xFF059669),
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
              },
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

String _formatAccountingCurrency(num amount) {
  final parts = amount.toStringAsFixed(2).split('.');
  final integerPart = parts[0];
  final decimalPart = parts[1];
  final regExp = RegExp(r'(\d+?)(?=(\d{3})+(?!\d))');
  final formattedInteger = integerPart.replaceAllMapped(regExp, (Match m) => '${m[1]},');
  return '₱$formattedInteger.$decimalPart';
}
