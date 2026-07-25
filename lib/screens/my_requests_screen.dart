import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../widgets/order_summary_sheet.dart';

class MyRequestsScreen extends StatelessWidget {
  const MyRequestsScreen({super.key});

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

  Future<void> _acceptOffer(BuildContext context, Map<String, dynamic> request, Map<String, dynamic> offer) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Accept this offer?', style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text('This will close your request and notify the merchant that you have accepted their offer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF6B57), foregroundColor: Colors.white),
            child: const Text('Yes, Accept'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final response = await Supabase.instance.client.from('requests').update({
        'status': 'matched',
        'accepted_offer_id': offer['id'],
      }).eq('id', request['id']).select();

      if (response.isEmpty) {
        throw Exception('Database did not update the row. Please check if RLS (Row Level Security) policies are blocking UPDATE access on the requests table.');
      }

      if (context.mounted) {
        // Send notification to the offer owner
        final offerOwnerId = offer['user_id'];
        if (offerOwnerId != null && offerOwnerId != AuthService.currentUserId) {
          final title = request['category'] ?? 'Request';
          await Supabase.instance.client.from('notifications').insert({
            'user_id': offerOwnerId,
            'title': 'Offer Accepted!',
            'body': 'Your offer was accepted for "$title". Please coordinate with the customer.',
            'type': 'offer_accepted',
            'reference_id': request['id'],
          });
        }
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 8),
              Text('Offer accepted! The merchant will be notified.'),
            ]),
            backgroundColor: Color(0xFF059669),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _cancelRequest(BuildContext context, String requestId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this Ping?', style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text('This will remove your Ping from the live feed and notify active merchants.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep Active')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            child: const Text('Cancel Ping'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final response = await Supabase.instance.client.from('requests').update({
        'status': 'cancelled',
      }).eq('id', requestId).select();
      
      if (response.isEmpty) {
        throw Exception('Database did not update the row. Please check RLS policies.');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
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
          .from('requests')
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

        final requests = snapshot.data ?? [];

        if (requests.isEmpty) {
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
                  child: const Icon(Icons.search_off_rounded, size: 48, color: Color(0xFF94A3B8)),
                ),
                const SizedBox(height: 16),
                const Text('No active Pings yet',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                const SizedBox(height: 6),
                const Text('Tap the button below to send\nyour first Ping!',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: requests.length,
          itemBuilder: (context, index) {
            final req = requests[index];
            return RequestWithOffersCard(
              request: req,
              onAccept: (offer) => _acceptOffer(context, req, offer),
              onCancel: () => _cancelRequest(context, req['id']),
              timeAgo: _timeAgo(req['created_at']),
            );
          },
        );
      },
    );
  }
}

class RequestWithOffersCard extends StatelessWidget {
  final Map<String, dynamic> request;
  final void Function(Map<String, dynamic> offer) onAccept;
  final VoidCallback onCancel;
  final String timeAgo;

  const RequestWithOffersCard({
    super.key,
    required this.request,
    required this.onAccept,
    required this.onCancel,
    required this.timeAgo,
  });

  Color _statusColor(String s) {
    switch (s) {
      case 'matched':   return const Color(0xFF059669);
      case 'cancelled': return const Color(0xFF94A3B8);
      default:          return const Color(0xFFD97706);
    }
  }

  Color _statusBg(String s) {
    switch (s) {
      case 'matched':   return const Color(0xFFF0FDF4);
      case 'cancelled': return const Color(0xFFF1F5F9);
      default:          return const Color(0xFFFFFBEB);
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'matched':   return '\u2705 Matched';
      case 'cancelled': return '\u26d4 Cancelled';
      default:          return '\ud83d\udfe1 Open';
    }
  }

  @override
  Widget build(BuildContext context) {
    final status      = request['status'] ?? 'active';
    final description = request['description'] ?? '';
    final category    = request['category'] ?? '';
    final maxBudget   = (request['max_budget'] ?? 0).toDouble();
    final acceptedId  = request['accepted_offer_id'];
    final isOpen      = status == 'active' || status == 'open';
    final isMatched   = status == 'matched';

    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isMatched ? const Color(0xFFD1FAE5) : const Color(0xFFE2E8F0),
          width: isMatched ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Request header
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(category,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
                      const SizedBox(height: 2),
                      Text(description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _statusBg(status),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(_statusLabel(status),
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _statusColor(status))),
                ),
              ],
            ),

            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.attach_money, size: 14, color: Color(0xFF004D40)),
              Text('Budget: \u20b1${maxBudget.toStringAsFixed(0)}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF004D40), fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(timeAgo, style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
            ]),

            // Cancel button for open Pings
            if (isOpen) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onCancel,
                  icon: const Icon(Icons.cancel_outlined, size: 14, color: Colors.redAccent),
                  label: const Text('Cancel Ping',
                      style: TextStyle(fontSize: 12, color: Colors.redAccent, fontWeight: FontWeight.w600)),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                ),
              ),
            ],

            const SizedBox(height: 14),
            const Divider(color: Color(0xFFE2E8F0), height: 1),
            const SizedBox(height: 14),

            // Offers section
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: Supabase.instance.client
                  .from('offers')
                  .stream(primaryKey: ['id'])
                  .eq('request_id', request['id'])
                  .order('offered_price', ascending: true),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF004D40))),
                    ),
                  );
                }

                final offers = snap.data!;

                if (offers.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Row(children: [
                      Icon(Icons.hourglass_empty, size: 14, color: Color(0xFF94A3B8)),
                      SizedBox(width: 6),
                      Text('Waiting for offers from merchants...',
                          style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8), fontStyle: FontStyle.italic)),
                    ]),
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${offers.length} Offer${offers.length > 1 ? 's' : ''} Received',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(height: 10),
                    ...offers.map((offer) {
                      final isAccepted  = acceptedId == offer['id'];
                      final price       = (offer['offered_price'] ?? 0).toDouble();
                      final shopName    = offer['seller_name'] ?? 'Merchant';
                      final note        = offer['note'] ?? '';

                      return GestureDetector(
                        onTap: isAccepted ? () {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            builder: (_) => OrderSummarySheet(request: request),
                          );
                        } : null,
                        child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: isAccepted ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isAccepted ? const Color(0xFFD1FAE5) : const Color(0xFFE2E8F0),
                            width: isAccepted ? 1.5 : 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(shopName,
                                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                                      const SizedBox(height: 2),
                                      Text('\u20b1${price.toStringAsFixed(2)}',
                                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF004D40), letterSpacing: -0.5)),
                                    ],
                                  ),
                                ),
                                if (isAccepted)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(color: const Color(0xFF10B981), borderRadius: BorderRadius.circular(12)),
                                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                      Icon(Icons.check, size: 12, color: Colors.white),
                                      SizedBox(width: 4),
                                      Text('Accepted', style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
                                    ]),
                                  )
                                else if (isOpen)
                                  ElevatedButton(
                                    onPressed: () => onAccept(offer),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF004D40),
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size(80, 36),
                                      padding: const EdgeInsets.symmetric(horizontal: 14),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    ),
                                    child: const Text('Accept', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                  ),
                              ],
                            ),
                            if (note.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(note, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                            ],
                          ],
                        ),
                      ),
                    );
                    }),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
