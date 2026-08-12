import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_service.dart';
import '../utils/transaction_number.dart';
import 'premium_button.dart';

class OrderSummarySheet extends StatefulWidget {
  final Map<String, dynamic> request;

  const OrderSummarySheet({super.key, required this.request});

  @override
  State<OrderSummarySheet> createState() => _OrderSummarySheetState();
}

class _OrderSummarySheetState extends State<OrderSummarySheet> {
  bool _isLoading = true;
  bool _isUpdating = false;
  String _error = '';

  Map<String, dynamic>? _offer;
  Map<String, dynamic>? _buyerProfile;
  Map<String, dynamic>? _merchantProfile;
  late Map<String, dynamic> _requestData;
  late Map<String, dynamic> _tags;

  @override
  void initState() {
    super.initState();
    _requestData = Map<String, dynamic>.from(widget.request);
    _tags = _parseTags(_requestData['tags']);
    _fetchDetails();
  }

  Map<String, dynamic> _parseTags(dynamic raw) {
    if (raw == null) return {};
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.isNotEmpty) {
      try {
        return Map<String, dynamic>.from(jsonDecode(raw));
      } catch (_) {}
    }
    return {};
  }

  // 'matched' -> 'ready' -> 'completed'
  String get _orderStage => (_tags['order_stage'] ?? 'matched').toString();
  bool get _isBuyer => AuthService.currentUserId == _requestData['user_id'];
  bool get _isMerchant => _offer != null && AuthService.currentUserId == _offer!['user_id'];

  Future<void> _fetchDetails() async {
    try {
      final supabase = Supabase.instance.client;
      var offerId = _requestData['accepted_offer_id'];
      Map<String, dynamic>? offerRes;

      if (offerId != null) {
        offerRes = await supabase.from('offers').select().eq('id', offerId).maybeSingle();
      }

      // Fallback: If accepted_offer_id wasn't set or offer not found by ID, look up offer by request_id
      if (offerRes == null) {
        final reqId = _requestData['id'];
        if (reqId != null) {
          offerRes = await supabase
              .from('offers')
              .select()
              .eq('request_id', reqId)
              .order('created_at', ascending: false)
              .limit(1)
              .maybeSingle();

          if (offerRes != null) {
            try {
              await supabase.from('requests').update({
                'accepted_offer_id': offerRes['id'],
                'status': 'matched',
              }).eq('id', reqId);
            } catch (_) {}
          }
        }
      }

      if (offerRes == null) {
        throw Exception('No accepted offer found for this request.');
      }
      _offer = offerRes;

      final buyerId = _requestData['user_id'];
      if (buyerId != null) {
        _buyerProfile = await supabase.from('profiles').select().eq('id', buyerId).maybeSingle();
      }

      final merchantId = offerRes['user_id'];
      if (merchantId != null) {
        _merchantProfile = await supabase.from('profiles').select().eq('id', merchantId).maybeSingle();
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _advanceStage(String newStage) async {
    setState(() => _isUpdating = true);
    final now = DateTime.now().toIso8601String();
    final updatedTags = Map<String, dynamic>.from(_tags);

    if (newStage == 'ready') {
      updatedTags['order_stage'] = 'ready';
      updatedTags['ready_at'] = now;
    } else if (newStage == 'completed') {
      updatedTags['order_stage'] = 'completed';
      updatedTags['completed_at'] = now;
      updatedTags['completed_by'] = _isBuyer ? 'buyer' : 'merchant';
    }

    // The stage change is the critical path — it must succeed and any
    // failure here is surfaced to the user.
    try {
      await Supabase.instance.client
          .from('requests')
          .update({'tags': jsonEncode(updatedTags)})
          .eq('id', _requestData['id']);
    } catch (e) {
      if (mounted) {
        setState(() => _isUpdating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update: $e'), backgroundColor: const Color(0xFFEF4444)),
        );
      }
      return;
    }

    if (mounted) {
      setState(() {
        _tags = updatedTags;
        _requestData = {..._requestData, 'tags': jsonEncode(updatedTags)};
        _isUpdating = false;
      });
    }

    // Notifying the other party is best-effort: it must never roll back or
    // mask the stage change above, which has already succeeded by this point.
    try {
      final merchantUserId = _offer?['user_id'];
      final otherPartyId = _isBuyer ? merchantUserId : _requestData['user_id'];
      if (otherPartyId != null && otherPartyId != AuthService.currentUserId) {
        final title = _requestData['category'] ?? 'Ping';
        final txn = transactionNumber(_requestData['id']);
        await Supabase.instance.client.from('notifications').insert({
          'user_id': otherPartyId,
          'title': newStage == 'ready' ? 'Order Ready' : 'Order Completed',
          'body': newStage == 'ready'
              ? '$txn — "$title" is ready. Coordinate the handover.'
              : '$txn — "$title" was marked complete. Thanks for using Ping!',
          'type': newStage == 'ready' ? 'order_ready' : 'order_completed',
          'reference_id': _requestData['id'],
        });
      }
    } catch (e) {
      debugPrint('Notification insert failed for stage=$newStage: $e');
    }
  }

  Future<void> _callNumber(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
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

  String _fulfillmentLabel(String type) {
    switch (type) {
      case 'delivery': return 'Delivery';
      case 'pickup':   return 'Store Pickup';
      case 'visit':    return 'On-Site Visit';
      case 'status':   return 'Status Check';
      case 'onsite':   return 'Come to Me';
      case 'go_to':    return 'At a Location';
      case 'remote':   return 'Remote Help';
      default:         return type;
    }
  }

  // Describes the fulfillment step once it's actually been reached (the
  // merchant marked the order ready) — past/present-tense, stated as fact.
  String _inProgressLabel(String type) {
    switch (type) {
      case 'delivery': return 'Out for Delivery';
      case 'pickup':   return 'Ready for Pickup';
      case 'visit':    return 'Visit Scheduled';
      case 'status':   return 'Status Shared';
      case 'onsite':   return 'Helper On the Way';
      case 'go_to':    return 'Helper Heading Out';
      case 'remote':   return 'Remote Help In Progress';
      default:         return 'In Progress';
    }
  }

  // Describes the same fulfillment step while it's still pending — shown as
  // the stepper's current/glowing step and the headline pill before that
  // step is actually reached, so it can't read as an already-true claim.
  String _pendingStepLabel(String type) {
    switch (type) {
      case 'delivery': return 'Preparing Delivery';
      case 'pickup':   return 'Preparing Pickup';
      case 'visit':    return 'Preparing Visit';
      case 'status':   return 'Preparing Status';
      case 'onsite':   return 'Preparing Helper';
      case 'go_to':    return 'Preparing Helper';
      case 'remote':   return 'Preparing Remote Help';
      default:         return 'In Progress';
    }
  }

  // Single source of truth for "what's happening right now" — the headline
  // pill and the stepper's current step both read from this so they can
  // never show two different words for the same state.
  String get _currentStatusLabel {
    final fulfillment = (_requestData['fulfillment_type'] ?? 'pickup').toString();
    return switch (_orderStage) {
      'completed' => 'Completed',
      'ready' => 'Awaiting Confirmation',
      _ => _pendingStepLabel(fulfillment),
    };
  }

  String _formatDateTime(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final hourInt = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '${months[dt.month - 1]} ${dt.day}, ${hourInt.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} $period';
  }

  Widget _buildPartyCard({
    required String title,
    required String name,
    required String phone,
    String? subtitle,
    required Color iconBg,
    required Color iconColor,
    required IconData icon,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 3)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(icon, color: iconColor),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.plusJakartaSans(fontSize: 11, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w700, letterSpacing: 0.4),
                ),
                const SizedBox(height: 2),
                if (subtitle != null) ...[
                  Text(subtitle, style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A))),
                  const SizedBox(height: 2),
                ],
                Text(
                  name.isNotEmpty ? name : 'Unknown Name',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: subtitle != null ? 13 : 15,
                    fontWeight: subtitle != null ? FontWeight.w600 : FontWeight.w800,
                    color: subtitle != null ? const Color(0xFF475569) : const Color(0xFF0F172A),
                  ),
                ),
              ],
            ),
          ),
          if (phone.isNotEmpty)
            GestureDetector(
              onTap: () => _callNumber(phone),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF004D40),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: const Color(0xFF004D40).withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 3)),
                  ],
                ),
                child: const Icon(Icons.call_rounded, color: Colors.white, size: 18),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStageStepper(String fulfillmentType) {
    final icons = [Icons.check_circle_rounded, Icons.local_shipping_rounded, Icons.verified_rounded];
    // 'Found' is always already achieved by the time this sheet can open,
    // so currentIndex points to the step still awaiting action.
    final currentIndex = switch (_orderStage) {
      'completed' => 3,
      'ready' => 2,
      _ => 1,
    };

    // Pending phrasing only applies to the step that's actually current —
    // a future step still shows its plain destination name, and a done
    // step shows the "this really happened" phrasing. Otherwise the same
    // word ends up describing three different truths.
    String labelFor(int stepIndex, bool isDone, bool isCurrent) {
      switch (stepIndex) {
        case 0:
          return 'Found';
        case 1:
          return isCurrent ? _pendingStepLabel(fulfillmentType) : _inProgressLabel(fulfillmentType);
        default:
          return isCurrent ? 'Awaiting Confirmation' : 'Completed';
      }
    }

    return Row(
      children: List.generate(icons.length * 2 - 1, (i) {
        if (i.isOdd) {
          final connectorDone = (i ~/ 2) < currentIndex;
          return Expanded(
            child: Container(
              height: 2,
              margin: const EdgeInsets.only(bottom: 20),
              color: connectorDone ? const Color(0xFF004D40) : const Color(0xFFE2E8F0),
            ),
          );
        }
        final stepIndex = i ~/ 2;
        final isDone = stepIndex < currentIndex;
        final isCurrent = stepIndex == currentIndex;
        final label = labelFor(stepIndex, isDone, isCurrent);
        final icon = icons[stepIndex];

        return Column(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDone
                    ? const Color(0xFF004D40)
                    : isCurrent
                        ? const Color(0xFFE28743)
                        : Colors.white,
                border: Border.all(
                  color: isDone || isCurrent ? Colors.transparent : const Color(0xFFCBD5E1),
                  width: 1.5,
                ),
                boxShadow: isCurrent
                    ? [BoxShadow(color: const Color(0xFFE28743).withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 3))]
                    : [],
              ),
              child: Icon(
                isDone ? Icons.check_rounded : icon,
                size: 18,
                color: isDone || isCurrent ? Colors.white : const Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 74,
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10.5,
                  fontWeight: isDone || isCurrent ? FontWeight.w800 : FontWeight.w600,
                  color: isDone
                      ? const Color(0xFF004D40)
                      : isCurrent
                          ? const Color(0xFFB45309)
                          : const Color(0xFF94A3B8),
                ),
              ),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildActionArea() {
    if (_orderStage == 'completed') {
      final completedAt = _formatDateTime(_tags['completed_at'] as String?);
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFF0FDF4),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFBBF7D0)),
        ),
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded, color: Colors.white, size: 30),
            ),
            const SizedBox(height: 12),
            Text('Transaction Completed', style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w800, color: const Color(0xFF15803D))),
            if (completedAt.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(completedAt, style: GoogleFonts.plusJakartaSans(fontSize: 12, color: const Color(0xFF15803D).withValues(alpha: 0.8))),
            ],
          ],
        ),
      );
    }

    // Not the buyer and not the merchant who won this request — e.g. another
    // merchant browsing a ping that already matched with someone else. Show
    // a neutral, role-agnostic status instead of assuming either side.
    if (!_isBuyer && !_isMerchant) {
      return _buildWaitingBanner(
        _orderStage == 'ready'
            ? '$_currentStatusLabel — fulfilled and being handed over.'
            : 'This request has already been matched with another shop.',
      );
    }

    if (_orderStage == 'ready') {
      if (_isBuyer) {
        return PremiumButton(
          onPressed: _isUpdating ? null : () => _advanceStage('completed'),
          isLoading: _isUpdating,
          color: const Color(0xFF004D40),
          borderRadius: BorderRadius.circular(16),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_rounded, size: 20, color: Colors.white),
              const SizedBox(width: 8),
              Text('Confirm Completed', style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
            ],
          ),
        );
      }
      return _buildWaitingBanner('$_currentStatusLabel — waiting for the customer to confirm they received it.');
    }

    // stage == 'matched'
    if (_isMerchant) {
      return Column(
        children: [
          PremiumButton(
            onPressed: _isUpdating ? null : () => _advanceStage('ready'),
            isLoading: _isUpdating,
            color: const Color(0xFFE28743),
            borderRadius: BorderRadius.circular(16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.local_shipping_rounded, size: 20, color: Colors.white),
                const SizedBox(width: 8),
                Text('Mark as Ready', style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Let the customer know their order is ready.',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(fontSize: 11.5, color: const Color(0xFF94A3B8)),
          ),
        ],
      );
    }

    // buyer, stage == 'matched'
    return Column(
      children: [
        _buildWaitingBanner('$_currentStatusLabel — the merchant is preparing your order.'),
        const SizedBox(height: 10),
        TextButton.icon(
          onPressed: _isUpdating ? null : () => _advanceStage('completed'),
          icon: const Icon(Icons.check_circle_outline_rounded, size: 16, color: Color(0xFF64748B)),
          label: const Text('Already received it? Mark as Completed', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF64748B))),
        ),
      ],
    );
  }

  Widget _buildWaitingBanner(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.hourglass_top_rounded, size: 16, color: Color(0xFF94A3B8)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: GoogleFonts.plusJakartaSans(fontSize: 12.5, color: const Color(0xFF64748B), fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  List<_LogEntry> _buildLogEntries(String fulfillmentType) {
    final entries = <_LogEntry>[];

    entries.add(_LogEntry(
      title: 'Ping Broadcasted',
      subtitle: 'Request sent to nearby shops',
      timestamp: _formatDateTime(_requestData['created_at'] as String?),
      icon: Icons.bolt_rounded,
      color: const Color(0xFF64748B),
    ));

    if (_offer != null) {
      final price = ((_offer!['offered_price'] ?? 0) as num).toStringAsFixed(2);
      entries.add(_LogEntry(
        title: 'Offer Received',
        subtitle: '${_offer!['seller_name'] ?? 'Merchant'} offered ₱$price',
        timestamp: _formatDateTime(_offer!['created_at'] as String?),
        icon: Icons.local_offer_rounded,
        color: const Color(0xFF2563EB),
      ));
    }

    final matchedAt = _tags['matched_at'] as String?;
    if (matchedAt != null) {
      entries.add(_LogEntry(
        title: 'Offer Accepted',
        subtitle: 'Matched with merchant',
        timestamp: _formatDateTime(matchedAt),
        icon: Icons.handshake_rounded,
        color: const Color(0xFF004D40),
      ));
    }

    final readyAt = _tags['ready_at'] as String?;
    if (readyAt != null) {
      entries.add(_LogEntry(
        title: 'Marked Ready',
        subtitle: _inProgressLabel(fulfillmentType),
        timestamp: _formatDateTime(readyAt),
        icon: Icons.local_shipping_rounded,
        color: const Color(0xFFB45309),
      ));
    }

    final completedAt = _tags['completed_at'] as String?;
    if (completedAt != null) {
      final completedBy = _tags['completed_by'] == 'merchant' ? 'the merchant' : 'the customer';
      entries.add(_LogEntry(
        title: 'Transaction Completed',
        subtitle: 'Confirmed by $completedBy',
        timestamp: _formatDateTime(completedAt),
        icon: Icons.verified_rounded,
        color: const Color(0xFF15803D),
      ));
    }

    return entries;
  }

  Widget _buildTransactionLog(String fulfillmentType) {
    final entries = _buildLogEntries(fulfillmentType);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.history_rounded, size: 16, color: Color(0xFF004D40)),
            const SizedBox(width: 8),
            Text('Transaction Log',
              style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A))),
          ]),
          const SizedBox(height: 18),
          ...List.generate(entries.length, (i) {
            final entry = entries[i];
            final isLast = i == entries.length - 1;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(color: entry.color.withValues(alpha: 0.12), shape: BoxShape.circle),
                      child: Icon(entry.icon, size: 14, color: entry.color),
                    ),
                    if (!isLast)
                      Container(
                        width: 2,
                        height: 34,
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        color: const Color(0xFFE2E8F0),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: isLast ? 0 : 12, top: 3),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(entry.title,
                                style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A))),
                            ),
                            if (entry.timestamp.isNotEmpty)
                              Text(entry.timestamp,
                                style: GoogleFonts.plusJakartaSans(fontSize: 10.5, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w600)),
                          ],
                        ),
                        if (entry.subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(entry.subtitle!,
                            style: GoogleFonts.plusJakartaSans(fontSize: 12, color: const Color(0xFF64748B))),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  void _copyTransactionNumber(String txn) {
    Clipboard.setData(ClipboardData(text: txn));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied $txn'),
        backgroundColor: const Color(0xFF004D40),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String category = _requestData['category'] ?? 'General';
    final String description = _requestData['description'] ?? '';
    final String fulfillment = _requestData['fulfillment_type'] ?? 'pickup';
    final categoryEmoji = _categoryEmoji(category);
    final txn = transactionNumber(_requestData['id']);

    // Same phrase and color language as the stepper's current step below —
    // the pill used to hardcode its own wording ("Found"/"Ready") that could
    // fall out of sync with what the stepper was actually highlighting.
    final stagePill = _orderStage == 'completed'
        ? (_currentStatusLabel, const Color(0xFFDCFCE7), const Color(0xFF15803D))
        : (_currentStatusLabel, const Color(0xFFFFF7ED), const Color(0xFFB45309));

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            children: [
              Center(
                child: Container(
                  width: 48,
                  height: 4,
                  decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('$categoryEmoji  ', style: const TextStyle(fontSize: 22)),
                  Text('Order Summary', style: GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w900, color: const Color(0xFF0F172A), letterSpacing: -0.5)),
                ],
              ),
              const SizedBox(height: 6),
              Center(
                child: GestureDetector(
                  onTap: () => _copyTransactionNumber(txn),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.receipt_long_rounded, size: 13, color: Color(0xFF94A3B8)),
                      const SizedBox(width: 5),
                      Text(txn, style: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF64748B), letterSpacing: 0.3)),
                      const SizedBox(width: 5),
                      const Icon(Icons.copy_rounded, size: 12, color: Color(0xFFCBD5E1)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(color: stagePill.$2, borderRadius: BorderRadius.circular(50)),
                  child: Text(stagePill.$1, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: stagePill.$3)),
                ),
              ),
              const SizedBox(height: 28),

              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.all(40.0),
                  child: Center(child: CircularProgressIndicator(color: Color(0xFF004D40))),
                )
              else if (_error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Text('Error: $_error', style: const TextStyle(color: Colors.red)),
                )
              else ...[
                // ── Progress Stepper ─────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _buildStageStepper(fulfillment),
                ),
                const SizedBox(height: 24),

                // ── Request Details Card ──────────────────────────────
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(color: const Color(0xFFE2F0F0), borderRadius: BorderRadius.circular(50)),
                            child: Text(category, style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF004D40))),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(description, style: GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A), height: 1.3)),
                      const SizedBox(height: 16),
                      const Divider(color: Color(0xFFE2E8F0), height: 1),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Fulfillment', style: GoogleFonts.plusJakartaSans(color: const Color(0xFF64748B), fontWeight: FontWeight.w600, fontSize: 13)),
                          Text(_fulfillmentLabel(fulfillment), style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, color: const Color(0xFF0F172A), fontSize: 13)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text('Agreed Price', style: GoogleFonts.plusJakartaSans(color: const Color(0xFF64748B), fontWeight: FontWeight.w600, fontSize: 13)),
                          Text(
                            '₱${((_offer?['offered_price'] ?? 0) as num).toStringAsFixed(2)}',
                            style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w900, color: const Color(0xFF004D40), letterSpacing: -0.3),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
                Text('Transaction Parties', style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A))),
                const SizedBox(height: 12),

                // Phone/call is withheld on whichever card represents the
                // current viewer themself — there's no reason to offer a
                // "call yourself" button next to your own contact info.
                _buildPartyCard(
                  title: 'CUSTOMER / BUYER',
                  name: _buyerProfile?['full_name'] ?? '',
                  phone: _isBuyer ? '' : (_buyerProfile?['contact_number'] ?? ''),
                  iconBg: const Color(0xFFE0E7FF),
                  iconColor: const Color(0xFF4F46E5),
                  icon: Icons.person_rounded,
                ),

                _buildPartyCard(
                  title: 'MERCHANT / RESPONDER',
                  subtitle: _offer?['seller_name'] ?? 'Shop',
                  name: _merchantProfile?['full_name'] ?? '',
                  phone: _isMerchant ? '' : (_merchantProfile?['contact_number'] ?? ''),
                  iconBg: const Color(0xFFDCFCE7),
                  iconColor: const Color(0xFF16A34A),
                  icon: Icons.storefront_rounded,
                ),

                const SizedBox(height: 24),
                _buildTransactionLog(fulfillment),

                const SizedBox(height: 20),
                _buildActionArea(),

                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      foregroundColor: const Color(0xFF64748B),
                    ),
                    child: const Text('Close', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _LogEntry {
  final String title;
  final String? subtitle;
  final String timestamp;
  final IconData icon;
  final Color color;

  _LogEntry({
    required this.title,
    this.subtitle,
    required this.timestamp,
    required this.icon,
    required this.color,
  });
}
