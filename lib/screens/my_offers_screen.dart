import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';

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
                const Text('No offers sent yet',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                const SizedBox(height: 6),
                const Text('Offers you send will appear here\nwith their acceptance status.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
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

                // Determine offer status
                String statusLabel;
                Color statusColor;
                Color statusBg;
                IconData statusIcon;

                if (reqMatched && isMyOfferWon) {
                  statusLabel = 'Accepted';
                  statusColor = const Color(0xFF059669);
                  statusBg    = const Color(0xFFF0FDF4);
                  statusIcon  = Icons.check_circle_rounded;
                } else if (reqMatched && !isMyOfferWon) {
                  statusLabel = 'Not Selected';
                  statusColor = const Color(0xFF64748B);
                  statusBg    = const Color(0xFFF1F5F9);
                  statusIcon  = Icons.cancel_outlined;
                } else if (reqStatus == 'active') {
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
                final category = request?['category'] ?? '';

                String catEmoji = '\ud83d\udccc';
                if (category.contains('Parts'))     catEmoji = '\ud83d\ude97';
                if (category.contains('Rider'))     catEmoji = '\ud83d\udce6';
                if (category.contains('Rooms'))     catEmoji = '\ud83c\udfe0';
                if (category.contains('Community')) catEmoji = '\ud83d\udccd';

                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: reqMatched && isMyOfferWon
                          ? const Color(0xFFD1FAE5)
                          : const Color(0xFFE2E8F0),
                    ),
                  ),
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
                                style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF0F172A),
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(color: statusBg, borderRadius: BorderRadius.circular(20)),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(statusIcon, size: 12, color: statusColor),
                                const SizedBox(width: 4),
                                Text(statusLabel,
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor)),
                              ]),
                            ),
                          ],
                        ),

                        const SizedBox(height: 14),
                        const Divider(color: Color(0xFFE2E8F0), height: 1),
                        const SizedBox(height: 14),

                        // Price + time
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const Text('Your Offer',
                                  style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              Text(
                                '\u20b1${price.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF004D40), letterSpacing: -0.5,
                                ),
                              ),
                            ]),
                            Text(timeAgo,
                                style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                          ],
                        ),

                        // Note
                        if (note.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(note,
                                style: const TextStyle(fontSize: 12, color: Color(0xFF475569))),
                          ),
                        ],

                        // Accepted banner
                        if (reqMatched && isMyOfferWon) ...[
                          const SizedBox(height: 14),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0FDF4),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFBBF7D0)),
                            ),
                            child: const Row(children: [
                              Text('\ud83c\udf89 ', style: TextStyle(fontSize: 16)),
                              Expanded(
                                child: Text(
                                  'Customer accepted your offer! Coordinate delivery or pickup.',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF059669)),
                                ),
                              ),
                            ]),
                          ),
                        ],
                      ],
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
        .select('id, description, category, status, accepted_offer_id')
        .inFilter('id', ids);
    return List<Map<String, dynamic>>.from(data);
  }
}
