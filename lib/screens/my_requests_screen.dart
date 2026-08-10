import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../utils/transaction_number.dart';
import '../widgets/order_summary_sheet.dart';

bool _isOrderCompleted(Map<String, dynamic> req) {
  final raw = req['tags'];
  Map<String, dynamic> tags = {};
  if (raw is Map) {
    tags = Map<String, dynamic>.from(raw);
  } else if (raw is String && raw.isNotEmpty) {
    try {
      tags = Map<String, dynamic>.from(jsonDecode(raw));
    } catch (_) {}
  }
  return tags['order_stage'] == 'completed';
}

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
  String _filter = 'active'; // 'active' | 'matched'

  StreamSubscription<List<Map<String, dynamic>>>? _sub;
  List<Map<String, dynamic>> _pings = [];
  bool _loading = true;
  String? _error;

  Timer? _debounce;
  List<Map<String, dynamic>>? _pendingSnapshot;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  void _subscribe() {
    final userId = AuthService.currentUserId;
    if (userId == null) return;
    _sub = Supabase.instance.client
        .from('requests')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .listen(_onSnapshot, onError: (e) {
      if (mounted) setState(() => _error = e.toString());
    });
  }

  // Realtime pushes a fresh full snapshot on every change to any of the
  // user's requests, even ones unrelated to what's visible. Debounce
  // bursts and skip the rebuild entirely when nothing render-relevant
  // actually changed, so the list doesn't flash on every DB event.
  void _onSnapshot(List<Map<String, dynamic>> data) {
    _pendingSnapshot = data;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      final incoming = _pendingSnapshot;
      if (incoming == null) return;
      if (!_loading && _isSameRenderState(_pings, incoming)) return;
      setState(() {
        _pings = incoming;
        _loading = false;
      });
    });
  }

  bool _isSameRenderState(List<Map<String, dynamic>> a, List<Map<String, dynamic>> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final ra = a[i];
      final rb = b[i];
      if (ra['id'] != rb['id'] ||
          ra['status'] != rb['status'] ||
          ra['accepted_offer_id'] != rb['accepted_offer_id'] ||
          ra['updated_at'] != rb['updated_at']) {
        return false;
      }
    }
    return true;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _sub?.cancel();
    super.dispose();
  }

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

    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF004D40)));
    }
    if (_error != null) {
      return Center(child: Text('Error: $_error'));
    }

    final rawRequests = _pings;

        // Strip cancelled and locally dismissed items
        final allPings = rawRequests.where((req) {
          final id = req['id'].toString();
          final status = (req['status'] ?? '').toString().toLowerCase();
          if (status == 'cancelled') return false;
          return !_dismissedIds.contains(id);
        }).toList();

        // Split by status; a 'matched' ping further splits into in-progress
        // vs completed based on tags.order_stage so finished orders move out
        // of the way instead of piling up in "Matched".
        final activePings = allPings.where((req) {
          final s = (req['status'] ?? '').toString().toLowerCase();
          return s == 'open' || s == 'active';
        }).toList();
        final matchedRaw = allPings.where((req) {
          return (req['status'] ?? '').toString().toLowerCase() == 'matched';
        }).toList();
        final matchedPings = matchedRaw.where((req) => !_isOrderCompleted(req)).toList();
        final completedPings = matchedRaw.where(_isOrderCompleted).toList();

        // Apply search filter to whichever tab is active
        var requests = switch (_filter) {
          'matched' => matchedPings,
          'completed' => completedPings,
          _ => activePings,
        };
        if (widget.searchQuery.trim().isNotEmpty) {
          final query = widget.searchQuery.toLowerCase().trim();
          requests = requests.where((req) {
            final category    = (req['category'] ?? '').toString().toLowerCase();
            final subCategory = (req['sub_category'] ?? '').toString().toLowerCase();
            final item        = (req['item_name'] ?? req['title'] ?? '').toString().toLowerCase();
            final notes       = (req['notes'] ?? req['description'] ?? '').toString().toLowerCase();
            final tags        = (req['tags'] ?? '').toString().toLowerCase();
            return category.contains(query) || subCategory.contains(query) ||
                   item.contains(query) || notes.contains(query) || tags.contains(query);
          }).toList();
        }

        final isSearching = widget.searchQuery.trim().isNotEmpty;

        return Column(
          children: [
            // ── Filter tabs ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _FilterTab(
                      label: 'Active',
                      count: activePings.length,
                      selected: _filter == 'active',
                      onTap: () => setState(() => _filter = 'active'),
                    ),
                    const SizedBox(width: 8),
                    _FilterTab(
                      label: 'Matched',
                      count: matchedPings.length,
                      selected: _filter == 'matched',
                      onTap: () => setState(() => _filter = 'matched'),
                      badge: matchedPings.isNotEmpty,
                    ),
                    const SizedBox(width: 8),
                    _FilterTab(
                      label: 'Completed',
                      count: completedPings.length,
                      selected: _filter == 'completed',
                      onTap: () => setState(() => _filter = 'completed'),
                    ),
                  ],
                ),
              ),
            ),

            // ── List ────────────────────────────────────────────────
            if (requests.isEmpty)
              Expanded(
                child: Center(
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
                        child: Icon(
                          isSearching
                              ? Icons.search_off_rounded
                              : switch (_filter) {
                                  'matched' => Icons.verified_rounded,
                                  'completed' => Icons.task_alt_rounded,
                                  _ => Icons.bolt_rounded,
                                },
                          size: 40,
                          color: const Color(0xFF94A3B8),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        isSearching
                            ? 'No matching Pings found'
                            : switch (_filter) {
                                'matched' => 'No matched Pings yet',
                                'completed' => 'No completed Pings yet',
                                _ => 'No active Pings yet',
                              },
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isSearching
                            ? 'Try searching for a different item or category.'
                            : switch (_filter) {
                                'matched' => 'Accepted offers will appear here once you match with a merchant.',
                                'completed' => 'Finished transactions will be archived here.',
                                _ => 'Tap Send Ping below to broadcast your first request!',
                              },
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 80),
                  itemCount: requests.length,
                  itemBuilder: (context, index) {
            final req = requests[index];
            final reqId = (req['id'] ?? index).toString();
            final isOpen = req['status'] == 'active' || req['status'] == 'open';

            return RepaintBoundary(
              key: ValueKey('rb_$reqId'),
              child: Dismissible(
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
            ),
            );
          },
                ),
              ),
          ],
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
      case 'completed': return const Color(0xFF15803D);
      case 'matched':   return const Color(0xFF059669);
      case 'cancelled': return const Color(0xFF94A3B8);
      default:          return const Color(0xFFD97706);
    }
  }

  Color _statusBg(String s) {
    switch (s) {
      case 'completed': return const Color(0xFFDCFCE7);
      case 'matched':   return const Color(0xFFF0FDF4);
      case 'cancelled': return const Color(0xFFF1F5F9);
      default:          return const Color(0xFFFFFBEB);
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'completed': return 'Completed';
      case 'matched':   return 'Matched';
      case 'cancelled': return 'Cancelled';
      default:          return 'Open';
    }
  }

  IconData _statusIcon(String s) {
    switch (s) {
      case 'completed': return Icons.task_alt_rounded;
      case 'matched':   return Icons.verified_rounded;
      case 'cancelled': return Icons.cancel_rounded;
      default:          return Icons.radio_button_checked_rounded;
    }
  }

  String _fulfillmentLabel(String? type) {
    switch (type) {
      case 'delivery': return 'Delivery';
      case 'visit':    return 'On-Site Visit';
      case 'status':   return 'Status Check';
      case 'onsite':   return 'Come to Me';
      case 'go_to':    return 'At a Location';
      case 'remote':   return 'Remote Help';
      default:         return 'Store Pickup';
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
    final effectiveStatus = (isMatched && tags['order_stage'] == 'completed') ? 'completed' : status;

    final vehicleModel  = tags['vehicle_model'] ?? tags['spec_1'];
    final partSpec      = tags['part_spec'] ?? tags['spec_2'];
    final aircon        = tags['aircon_preferred'] == true;
    final txn           = transactionNumber(request['id']);

    final authUser   = AuthService.currentUser;
    final posterName = (authUser?.userMetadata?['full_name'] as String?)?.trim().isNotEmpty == true
        ? authUser!.userMetadata!['full_name'] as String
        : (authUser?.email ?? 'You');
    final posterInitial = posterName.isNotEmpty ? posterName[0].toUpperCase() : 'Y';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: isMatched ? const Color(0xFFECFDF5) : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isMatched ? const Color(0xFF86EFAC) : const Color(0xFFE2E8F0),
          width: isMatched ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Who posted it, and where it stands — identity leads,
            // status trails, so cards read like a feed of requests
            // rather than an anonymous list of tickets ──
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: const Color(0xFF004D40),
                  child: Text(
                    posterInitial,
                    style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              posterName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(50),
                            ),
                            child: const Text(
                              'You',
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFF64748B), letterSpacing: 0.3),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        formattedDate,
                        style: GoogleFonts.plusJakartaSans(fontSize: 11, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: _statusBg(effectiveStatus),
                    borderRadius: BorderRadius.circular(50),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_statusIcon(effectiveStatus), size: 13, color: _statusColor(effectiveStatus)),
                      const SizedBox(width: 5),
                      Text(
                        _statusLabel(effectiveStatus),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: _statusColor(effectiveStatus),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),
            const Divider(color: Color(0xFFF1F5F9), height: 1),
            const SizedBox(height: 14),

            // ── What was asked ────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: isMatched ? const Color(0xFFDCFCE7) : const Color(0xFFE2F0F0),
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: Text(
                      '$category  ·  ${_fulfillmentLabel(fulfillmentType)}',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isMatched ? const Color(0xFF15803D) : const Color(0xFF004D40),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                if (subCategory != null && subCategory.toString().isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: Text(
                      subCategory.toString(),
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFFB45309)),
                    ),
                  ),
                ],
              ],
            ),

            const SizedBox(height: 12),

            // ── Description ─────────────────────────────────────────
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

            // ── Spec Chips ──────────────────────────────────────────
            if (vehicleModel != null || partSpec != null || aircon) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (vehicleModel != null && vehicleModel.toString().isNotEmpty)
                      _SpecChip(
                        icon: Icons.directions_car_rounded,
                        label: vehicleModel.toString(),
                        iconColor: const Color(0xFF2563EB),
                        textColor: const Color(0xFF1E40AF),
                      ),
                    if (partSpec != null && partSpec.toString().isNotEmpty)
                      _SpecChip(
                        icon: Icons.build_rounded,
                        label: partSpec.toString(),
                        iconColor: const Color(0xFF7C3AED),
                        textColor: const Color(0xFF6D28D9),
                      ),
                    if (aircon)
                      const _SpecChip(
                        icon: Icons.ac_unit_rounded,
                        label: 'Aircon Preferred',
                        iconColor: Color(0xFF059669),
                        textColor: Color(0xFF047857),
                      ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),
            const Divider(color: Color(0xFFEFF2F6), height: 1),
            const SizedBox(height: 14),

            // ── Budget + Reference ────────────────────────────────────
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
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF94A3B8),
                        letterSpacing: 0.8,
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
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    txn,
                    style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8), fontWeight: FontWeight.w700, letterSpacing: 0.3),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),
            const Divider(color: Color(0xFFEFF2F6), height: 1),
            const SizedBox(height: 12),

            // ── Offers ───────────────────────────────────────────────
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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(50),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.wifi_tethering_rounded, size: 13, color: Color(0xFF10B981)),
                SizedBox(width: 8),
                Text(
                  'Listening for merchant offers...',
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
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isAccepted ? const Color(0xFFF0FDF4) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isNew
                        ? const Color(0xFFDC2626)
                        : (isAccepted ? const Color(0xFF86EFAC) : const Color(0xFFEFF2F6)),
                    width: isNew ? 1.5 : (isAccepted ? 1.5 : 1),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: isAccepted ? const Color(0xFF10B981) : const Color(0xFF004D40),
                          child: Text(
                            shopName.isNotEmpty ? shopName[0].toUpperCase() : 'M',
                            style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      shopName,
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (isNew) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFDC2626),
                                        borderRadius: BorderRadius.circular(50),
                                      ),
                                      child: const Text(
                                        'NEW',
                                        style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.5),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              Text(
                                _formatAccountingCurrency(price),
                                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w900, color: const Color(0xFF004D40)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Accept / Accepted button
                        if (isAccepted)
                          GestureDetector(
                            onTap: () => showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              builder: (_) => OrderSummarySheet(request: widget.request),
                            ),
                            child: Container(
                              height: 44,
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981),
                                borderRadius: BorderRadius.circular(50),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.verified_rounded, size: 15, color: Colors.white),
                                  SizedBox(width: 6),
                                  Text('Accepted', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
                                ],
                              ),
                            ),
                          )
                        else if (widget.isOpen)
                          GestureDetector(
                            onTap: () => widget.onAccept(offer),
                            child: Container(
                              height: 44,
                              padding: const EdgeInsets.symmetric(horizontal: 18),
                              decoration: BoxDecoration(
                                color: const Color(0xFF004D40),
                                borderRadius: BorderRadius.circular(50),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF004D40).withValues(alpha: 0.25),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_rounded, size: 16, color: Colors.white),
                                  SizedBox(width: 6),
                                  Text('Accept', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white)),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (note.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '“$note”',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: Color(0xFF475569), fontStyle: FontStyle.italic),
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

class _FilterTab extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final bool badge;
  final VoidCallback onTap;

  const _FilterTab({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
    this.badge = false,
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
                  color: selected
                      ? Colors.white.withValues(alpha: 0.25)
                      : (badge ? const Color(0xFF10B981) : const Color(0xFFE2E8F0)),
                  borderRadius: BorderRadius.circular(50),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: selected
                        ? Colors.white
                        : (badge ? Colors.white : const Color(0xFF64748B)),
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

String _formatAccountingCurrency(num amount) {
  final parts = amount.toStringAsFixed(2).split('.');
  final integerPart = parts[0];
  final decimalPart = parts[1];
  final regExp = RegExp(r'(\d+?)(?=(\d{3})+(?!\d))');
  final formattedInteger = integerPart.replaceAllMapped(regExp, (Match m) => '${m[1]},');
  return '₱$formattedInteger.$decimalPart';
}
