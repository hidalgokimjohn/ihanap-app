import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../widgets/order_summary_sheet.dart';

class MyRequestsScreen extends StatefulWidget {
  final String searchQuery;

  const MyRequestsScreen({
    super.key,
    this.searchQuery = '',
  });

  @override
  State<MyRequestsScreen> createState() => _MyRequestsScreenState();
}

class _MyRequestsScreenState extends State<MyRequestsScreen> {
  final Set<String> _dismissedIds = {};

  String _formatDateTime(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final month = months[dt.month - 1];
    final day = dt.day.toString().padLeft(2, '0');
    final year = dt.year;
    final hourInt = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final hour = hourInt.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$month $day, $year • $hour:$minute $period';
  }

  Future<void> _acceptOffer(BuildContext context, Map<String, dynamic> request, Map<String, dynamic> offer) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Accept this offer?', style: TextStyle(fontWeight: FontWeight.w800)),
        content: const Text('This will close your request and notify the merchant that you have accepted their offer.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF004D40), foregroundColor: Colors.white),
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
        throw Exception('Database did not update the row.');
      }

      if (context.mounted) {
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
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  Future<void> _cancelRequest(BuildContext context, String requestId) async {
    try {
      final response = await Supabase.instance.client.from('requests').update({
        'status': 'cancelled',
      }).eq('id', requestId).select();

      if (response.isEmpty) {
        throw Exception('Failed to update request status.');
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ping cancelled and archived successfully'),
            backgroundColor: Color(0xFF64748B),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _dismissedIds.remove(requestId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error cancelling request: $e'), behavior: SnackBarBehavior.floating),
        );
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

        var rawRequests = snapshot.data ?? [];

        // Optimistically filter out locally dismissed items & cancelled pings to declutter
        var requests = rawRequests.where((req) {
          final id = req['id'].toString();
          final status = (req['status'] ?? '').toString().toLowerCase();
          if (status == 'cancelled') return false;
          return !_dismissedIds.contains(id);
        }).toList();

        if (widget.searchQuery.trim().isNotEmpty) {
          final query = widget.searchQuery.toLowerCase().trim();
          requests = requests.where((req) {
            final category = (req['category'] ?? '').toString().toLowerCase();
            final subCategory = (req['sub_category'] ?? '').toString().toLowerCase();
            final item = (req['item_name'] ?? req['title'] ?? '').toString().toLowerCase();
            final notes = (req['notes'] ?? req['description'] ?? '').toString().toLowerCase();
            final status = (req['status'] ?? '').toString().toLowerCase();
            final tags = (req['tags'] ?? '').toString().toLowerCase();
            return category.contains(query) || subCategory.contains(query) || item.contains(query) || notes.contains(query) || status.contains(query) || tags.contains(query);
          }).toList();
        }

        if (requests.isEmpty) {
          final isFilter = widget.searchQuery.trim().isNotEmpty;
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Icon(isFilter ? Icons.search_off_rounded : Icons.bolt_rounded, size: 40, color: const Color(0xFF94A3B8)),
                ),
                const SizedBox(height: 12),
                Text(isFilter ? 'No matching Pings found' : 'No active Pings yet',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                const SizedBox(height: 4),
                Text(isFilter ? 'Try searching for a different item or category.' : 'Tap the button below to send your first Ping!',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          itemCount: requests.length,
          itemBuilder: (context, index) {
            final req = requests[index];
            final reqId = (req['id'] ?? index).toString();
            final isOpen = req['status'] == 'active' || req['status'] == 'open';

            return Dismissible(
              key: Key('ping_$reqId'),
              direction: isOpen ? DismissDirection.endToStart : DismissDirection.none,
              confirmDismiss: (direction) async {
                return await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    title: const Text('Cancel / Archive Ping?', style: TextStyle(fontWeight: FontWeight.w800)),
                    content: const Text('Are you sure you want to cancel and archive this Ping?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep Active')),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), foregroundColor: Colors.white),
                        child: const Text('Cancel & Archive', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                );
              },
              onDismissed: (direction) {
                // Immediately remove from local state to prevent "Dismissible widget is still part of the tree" error
                setState(() {
                  _dismissedIds.add(reqId);
                });
                _cancelRequest(context, reqId);
              },
              background: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.only(right: 20),
                alignment: Alignment.centerRight,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFCA5A5)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Icon(Icons.archive_outlined, color: Color(0xFFEF4444), size: 20),
                    SizedBox(width: 6),
                    Text(
                      'Swipe to Cancel',
                      style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ],
                ),
              ),
              child: RequestWithOffersCard(
                request: req,
                onAccept: (offer) => _acceptOffer(context, req, offer),
                onCancel: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      title: const Text('Cancel this Ping?', style: TextStyle(fontWeight: FontWeight.w800)),
                      content: const Text('This will remove your Ping from the live feed and notify active merchants.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep Active')),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                          child: const Text('Yes, Cancel Ping'),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true && mounted) {
                    setState(() {
                      _dismissedIds.add(reqId);
                    });
                    _cancelRequest(context, reqId);
                  }
                },
                formattedDate: _formatDateTime(req['created_at']),
              ),
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
  final String formattedDate;

  const RequestWithOffersCard({
    super.key,
    required this.request,
    required this.onAccept,
    required this.onCancel,
    required this.formattedDate,
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
      case 'matched':   return '✅ Matched';
      case 'cancelled': return '⛔ Cancelled';
      default:          return '🟢 Open';
    }
  }

  String _fulfillmentLabel(String? type) {
    switch (type) {
      case 'delivery': return '🛵 Delivery';
      case 'visit':    return '🛠️ On-Site Visit';
      case 'status':   return '📍 Status Check';
      default:         return '🏬 Store Pickup';
    }
  }

  Map<String, dynamic> _parseTags(dynamic rawTags) {
    if (rawTags == null) return {};
    if (rawTags is Map<String, dynamic>) return rawTags;
    if (rawTags is String && rawTags.isNotEmpty) {
      try {
        return Map<String, dynamic>.from(jsonDecode(rawTags));
      } catch (e) {
        debugPrint('Error parsing tags: $e');
      }
    }
    return {};
  }

  @override
  Widget build(BuildContext context) {
    final status          = request['status'] ?? 'active';
    final description     = request['description'] ?? request['item_name'] ?? '';
    final category        = request['category'] ?? 'General';
    final subCategory     = request['sub_category'];
    final fulfillmentType = request['fulfillment_type'];
    final maxBudget       = (request['max_budget'] ?? 0).toDouble();
    final acceptedId      = request['accepted_offer_id'];
    final isOpen          = status == 'active' || status == 'open';
    final isMatched       = status == 'matched';
    final tags            = _parseTags(request['tags']);

    final vehicleModel  = tags['vehicle_model'] ?? tags['spec_1'];
    final partSpec      = tags['part_spec'] ?? tags['spec_2'];
    final aircon        = tags['aircon_preferred'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isMatched ? const Color(0xFFD1FAE5) : const Color(0xFFE2E8F0),
          width: isMatched ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row: Category + Fulfillment Pill (Left) & Status Badge (Right)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2F0F0),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$category • ${_fulfillmentLabel(fulfillmentType)}',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF004D40),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusBg(status),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _statusColor(status).withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: _statusColor(status),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _statusLabel(status),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: _statusColor(status),
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            if (subCategory != null && subCategory.toString().isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Text(
                  '🏷️ ${subCategory.toString()}',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFD97706)),
                ),
              ),
            ],

            const SizedBox(height: 12),

            // Item Title / Main Request Description
            Text(
              description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
                height: 1.3,
              ),
            ),

            // Item Specifications Box (Vehicle, Spec, Aircon)
            if (vehicleModel != null || partSpec != null || aircon) ...[
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
                    if (vehicleModel != null && vehicleModel.toString().isNotEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.directions_car_outlined, size: 13, color: Color(0xFF2563EB)),
                          const SizedBox(width: 4),
                          Text(
                            vehicleModel.toString(),
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF1E40AF)),
                          ),
                        ],
                      ),
                    if (partSpec != null && partSpec.toString().isNotEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.build_circle_outlined, size: 13, color: Color(0xFF7C3AED)),
                          const SizedBox(width: 4),
                          Text(
                            partSpec.toString(),
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF6D28D9)),
                          ),
                        ],
                      ),
                    if (aircon)
                      const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.ac_unit_rounded, size: 13, color: Color(0xFF059669)),
                          SizedBox(width: 4),
                          Text(
                            'Aircon Preferred',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF047857)),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 14),

            // Footer Highlights: Spotter Tip / Budget (Left) & Date Timestamp (Right)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
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
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF004D40),
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Icon(Icons.schedule_rounded, size: 12, color: Color(0xFF94A3B8)),
                    const SizedBox(width: 4),
                    Text(
                      formattedDate,
                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 12),
            const Divider(color: Color(0xFFE2E8F0), height: 1),
            const SizedBox(height: 12),

            // Live Merchant Offers Section
            _OffersList(
              request: request,
              isOpen: isOpen,
              acceptedId: acceptedId,
              onAccept: onAccept,
            ),
          ],
        ),
      ),
    );
  }
}

class _OffersList extends StatefulWidget {
  final Map<String, dynamic> request;
  final bool isOpen;
  final dynamic acceptedId;
  final void Function(Map<String, dynamic> offer) onAccept;

  const _OffersList({
    required this.request,
    required this.isOpen,
    required this.acceptedId,
    required this.onAccept,
  });

  @override
  State<_OffersList> createState() => _OffersListState();
}

class _OffersListState extends State<_OffersList> {
  final Set<String> _seenOfferIds = {};
  bool _firstLoad = true;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('offers')
          .stream(primaryKey: ['id'])
          .eq('request_id', widget.request['id'])
          .order('offered_price', ascending: true),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const SizedBox(
            height: 24,
            child: Center(
              child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF004D40))),
            ),
          );
        }

        final offers = snap.data!;
        final currentIds = offers.map((o) => o['id'].toString()).toSet();
        final newIds = _firstLoad ? <String>{} : currentIds.difference(_seenOfferIds);
        _firstLoad = false;
        _seenOfferIds
          ..clear()
          ..addAll(currentIds);

        if (offers.isEmpty) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              children: [
                Icon(Icons.sensors_rounded, size: 14, color: Color(0xFF10B981)),
                SizedBox(width: 8),
                Text(
                  'Radar active • Waiting for local merchant offers...',
                  style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontStyle: FontStyle.italic),
                ),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.local_offer_rounded, size: 14, color: Color(0xFF004D40)),
                const SizedBox(width: 6),
                Text(
                  '${offers.length} Offer${offers.length > 1 ? 's' : ''} Received',
                  style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                ),
                if (newIds.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDC2626),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${newIds.length} NEW',
                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.3),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            ...offers.map((offer) {
              final offerId     = offer['id'].toString();
              final isAccepted  = widget.acceptedId == offer['id'];
              final isNew       = newIds.contains(offerId);
              final price       = (offer['offered_price'] ?? 0).toDouble();
              final shopName    = offer['seller_name'] ?? 'Merchant';
              final note        = offer['note'] ?? '';

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isAccepted ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isNew
                        ? const Color(0xFFDC2626)
                        : (isAccepted ? const Color(0xFF86EFAC) : const Color(0xFFE2E8F0)),
                    width: isNew ? 1.5 : (isAccepted ? 1.5 : 1),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: isAccepted ? const Color(0xFF10B981) : const Color(0xFF004D40),
                          child: Text(
                            shopName.isNotEmpty ? shopName[0].toUpperCase() : 'M',
                            style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      shopName,
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (isNew) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFDC2626),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: const Text(
                                        'NEW',
                                        style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.3),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              Text(
                                _formatAccountingCurrency(price),
                                style: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w900, color: const Color(0xFF004D40)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (isAccepted)
                          ElevatedButton.icon(
                            onPressed: () => showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              builder: (_) => OrderSummarySheet(request: widget.request),
                            ),
                            icon: const Icon(Icons.check_circle_rounded, size: 13, color: Colors.white),
                            label: const Text('Accepted', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          )
                        else if (widget.isOpen)
                          ElevatedButton(
                            onPressed: () => widget.onAccept(offer),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF004D40),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text('Accept', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),
                    if (note.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFF1F5F9)),
                        ),
                        child: Text(
                          '"$note"',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10, color: Color(0xFF475569), fontStyle: FontStyle.italic),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
          ],
        );
      },
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
