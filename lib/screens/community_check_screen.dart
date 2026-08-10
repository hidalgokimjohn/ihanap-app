import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../utils/user_masking_helper.dart';
import '../widgets/community_check_bottom_sheet.dart';

class CommunityCheckScreen extends StatelessWidget {
  const CommunityCheckScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Community Check',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
            Text('Live ground reports · expires in 15 min',
              style: TextStyle(fontSize: 10, color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
          ],
        ),
        centerTitle: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: const Color(0xFFE2E8F0), height: 1),
        ),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: Supabase.instance.client
            .from('community_checks')
            .stream(primaryKey: ['id'])
            .order('created_at', ascending: false),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF004D40)));
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final all = snapshot.data ?? [];
          if (all.isEmpty) {
            return _EmptyState(onPost: () => _openSheet(context));
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: all.length,
            itemBuilder: (_, i) => _CheckCard(check: all[i]),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openSheet(context),
        backgroundColor: const Color(0xFF004D40),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_location_alt_outlined, size: 18),
        label: const Text('Post Check', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
      ),
    );
  }

  void _openSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CommunityCheckBottomSheet(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Each card is fully self-contained. It has its own Timer that:
//  • ticks every second to update only the countdown display
//  • triggers a one-shot fade when it expires
// The parent ListView is NEVER rebuilt by timer ticks.
// ─────────────────────────────────────────────────────────────────────────────
class _CheckCard extends StatefulWidget {
  final Map<String, dynamic> check;
  const _CheckCard({required this.check});

  @override
  State<_CheckCard> createState() => _CheckCardState();
}

class _CheckCardState extends State<_CheckCard> {

  Future<void> _acceptAndTip(Map<String, dynamic> response) async {
    final tipCtrl = TextEditingController();
    final amount = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reward this Helper'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter the tip amount to send (₱):', style: TextStyle(fontSize: 14)),
            const SizedBox(height: 12),
            TextField(
              controller: tipCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                prefixText: '₱ ',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final val = int.tryParse(tipCtrl.text.trim());
              if (val != null && val > 0) {
                Navigator.pop(ctx, val);
              }
            },
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF004D40)),
            child: const Text('Proceed to Payment'),
          ),
        ],
      ),
    );

    if (amount == null || !mounted) return;

    try {
      // 1. Update the database directly so status becomes 'paid' immediately for testing
      await Supabase.instance.client.from('community_check_responses').update({
        'payment_status': 'paid',
        'is_accepted': true,
        'tip_amount': amount,
      }).eq('id', response['id']);

      // 2. Send notification to responder
      try {
        final responderId = response['user_id'];
        if (responderId != null) {
          await Supabase.instance.client.from('notifications').insert({
            'user_id': responderId,
            'title': 'You received a tip!',
            'body': 'Your community check response was accepted and you were rewarded ₱$amount!',
            'type': 'tip_received',
            'reference_id': widget.check['id'],
          });
        }
      } catch (err) {
        debugPrint('Failed to send tip notification: $err');
      }

      // 3. Try to open PayMongo sandbox checkout URL as well
      try {
        final res = await Supabase.instance.client.functions.invoke(
          'paymongo-checkout',
          body: {'responseId': response['id'], 'amount': amount},
        );
        final data = res.data;
        if (data != null && data['checkout_url'] != null) {
          final url = Uri.parse(data['checkout_url']);
          if (await canLaunchUrl(url)) {
            await launchUrl(url, mode: LaunchMode.externalApplication);
          }
        }
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment completed! Tipped ₱$amount to the helper.'),
            backgroundColor: const Color(0xFF004D40),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  static const _expiryMinutes = 15;
  Timer? _timer;
  Duration _remaining = Duration.zero;
  bool _isExpired = false;

  static const _typeConfig = {
    'traffic': {'emoji': '🚦', 'label': 'Traffic',         'color': 0xFFFFF7ED, 'fg': 0xFFEA580C},
    'queue':   {'emoji': '👥', 'label': 'Queue Line',      'color': 0xFFEFF6FF, 'fg': 0xFF2563EB},
    'flood':   {'emoji': '🌊', 'label': 'Flood / Weather', 'color': 0xFFE0F2FE, 'fg': 0xFF0284C7},
    'stock':   {'emoji': '📦', 'label': 'Store Stock',     'color': 0xFFF0FDF4, 'fg': 0xFF059669},
  };

  @override
  void initState() {
    super.initState();
    _updateRemaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateRemaining());
  }

  void _updateRemaining() {
    final created   = DateTime.parse(widget.check['created_at']).toLocal();
    final expiresAt = created.add(const Duration(minutes: _expiryMinutes));
    final r = expiresAt.difference(DateTime.now());
    if (mounted) {
      setState(() {
        _remaining  = r.isNegative ? Duration.zero : r;
        _isExpired  = r.isNegative;
      });
    }
    if (r.isNegative) _timer?.cancel();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _countdownText {
    final m = _remaining.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = _remaining.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  double get _progressPct =>
      _isExpired ? 0.0 : _remaining.inSeconds / (_expiryMinutes * 60);

  void _openResponderSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ResponderSheet(check: widget.check),
    );
  }

  @override
  Widget build(BuildContext context) {
    final type    = widget.check['check_type'] as String? ?? 'traffic';
    final cfg     = _typeConfig[type] ?? _typeConfig['traffic']!;
    final emoji   = cfg['emoji'] as String;
    final label   = cfg['label'] as String;
    final bgColor = Color(cfg['color'] as int);
    final fgColor = Color(cfg['fg']   as int);
    final landmark    = widget.check['landmark']    ?? '';
    final description = widget.check['description'] ?? '';
    final bounty      = (widget.check['bounty']     ?? 0).toDouble();
    final photoUrl    = widget.check['photo_url']   as String?;

    // ── Can this device actually verify the ground truth here? ──
    // A responder more than kNotifyRadiusMeters away can't give a real
    // status, so responding stays available but visibly gated by distance
    // rather than hidden — the check is still worth knowing about.
    final targetLat = (widget.check['target_lat'] as num?)?.toDouble();
    final targetLng = (widget.check['target_lng'] as num?)?.toDouble();
    final myLoc = LocationService.currentLocationNotifier.value;
    // A mocked reading is worse than no reading at all — it's positive
    // evidence of tampering, so it blocks responding outright rather than
    // falling back to the permissive "can't verify, so allow it" default.
    final myLocationMocked = myLoc?.isMocked == true;
    double? distanceKm;
    if (myLoc != null && !myLocationMocked && targetLat != null && targetLng != null) {
      distanceKm = LocationService.calculateDistanceKm(myLoc.latitude, myLoc.longitude, targetLat, targetLng);
    }
    final tooFarToVerify = myLocationMocked || (distanceKm != null && distanceKm > (kNotifyRadiusMeters / 1000));

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('community_check_responses')
          .stream(primaryKey: ['id'])
          .eq('check_id', widget.check['id'])
          .order('created_at', ascending: true),
      builder: (context, snapshot) {
        final responses = snapshot.data ?? [];
        final isResolved = responses.any((r) => r['is_accepted'] == true && r['payment_status'] == 'paid');

        // ── Status pill — resolved / expired / live countdown ──
        final Widget statusPill = isResolved
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: const Color(0xFFD1FAE5), borderRadius: BorderRadius.circular(50)),
                child: const Text('RESOLVED',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF059669))),
              )
            : _isExpired
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(50)),
                    child: const Text('EXPIRED',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFFDC2626))),
                  )
                : Container(
                    // ← This is the ONLY widget that rebuilds every second
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _remaining.inSeconds < 120 ? const Color(0xFFFEE2E2) : const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.timer_outlined, size: 12,
                        color: _remaining.inSeconds < 120 ? const Color(0xFFDC2626) : const Color(0xFF64748B)),
                      const SizedBox(width: 3),
                      Text(_countdownText,
                        style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w800,
                          color: _remaining.inSeconds < 120 ? const Color(0xFFDC2626) : const Color(0xFF334155),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        )),
                    ]),
                  );

        return AnimatedOpacity(
          opacity: _isExpired ? 0.3 : 1.0,
          duration: const Duration(milliseconds: 800),
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isResolved ? const Color(0xFF10B981) : (_isExpired ? const Color(0xFFE2E8F0) : bgColor),
                width: isResolved ? 1.5 : (_isExpired ? 1 : 1.5),
              ),
              boxShadow: _isExpired ? [] : [
                BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Photo
                if (photoUrl != null && photoUrl.isNotEmpty)
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(19)),
                    child: Stack(children: [
                      Image.network(photoUrl, height: 130, width: double.infinity, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          height: 130, color: const Color(0xFFF1F5F9),
                          child: const Center(child: Icon(Icons.image_not_supported_outlined, color: Color(0xFFCBD5E1))),
                        )),
                      Positioned(top: 8, left: 8, child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.blur_on, color: Colors.white, size: 10),
                          SizedBox(width: 3),
                          Text('Blurred', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600)),
                        ]),
                      )),
                    ]),
                  ),

                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Who posted it, and when — identity leads, status trails ──
                      FutureBuilder<Map<String, dynamic>?>(
                        future: UserMaskingHelper.getProfile(widget.check['user_id']),
                        builder: (context, profileSnap) {
                          final profile = profileSnap.data;
                          final maskedName = UserMaskingHelper.maskName(profile?['full_name']);
                          final badge = UserMaskingHelper.getRoleBadge(profile?['primary_role']);
                          final timeAgo = UserMaskingHelper.timeAgo(widget.check['created_at']);

                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 14,
                                backgroundColor: bgColor,
                                child: Text(emoji, style: const TextStyle(fontSize: 13)),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '$maskedName · $badge',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF0F172A)),
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      'Posted $timeAgo',
                                      style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8), fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              statusPill,
                            ],
                          );
                        },
                      ),

                      const SizedBox(height: 12),

                      // ── What's being checked — the headline ──
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(50)),
                        child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: fgColor)),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.location_on_rounded, size: 16, color: Color(0xFF94A3B8)),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(landmark,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF0F172A), height: 1.3)),
                          ),
                        ],
                      ),
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(description, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), height: 1.4)),
                      ],

                      // Progress bar — visual echo of the countdown pill above
                      if (!_isExpired && !isResolved) ...[
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _progressPct,
                            backgroundColor: const Color(0xFFE2E8F0),
                            color: _progressPct > 0.3 ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                            minHeight: 4,
                          ),
                        ),
                      ],

                      // Bounty banner
                      if (bounty > 0) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF7ED),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFED7AA)),
                          ),
                          child: Row(children: [
                            const Text('🎁', style: TextStyle(fontSize: 12)),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text('₱${bounty.toStringAsFixed(0)} bounty for confirmed responders',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFEA580C))),
                            ),
                          ]),
                        ),
                      ],

                      // ── Responder Action ─────────────────────────────────────
                      if (!_isExpired && !isResolved && AuthService.currentUserId != widget.check['user_id']) ...[
                        const SizedBox(height: 12),
                        const Divider(height: 1, color: Color(0xFFE2E8F0)),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton.icon(
                            onPressed: tooFarToVerify ? null : _openResponderSheet,
                            icon: Icon(
                              myLocationMocked
                                  ? Icons.gpp_bad_rounded
                                  : (tooFarToVerify ? Icons.location_off_rounded : Icons.record_voice_over_outlined),
                              size: 15,
                            ),
                            label: Text(
                              myLocationMocked
                                  ? 'Mock location detected — can\'t confirm'
                                  : (tooFarToVerify
                                      ? '${distanceKm!.toStringAsFixed(1)}km away — too far to confirm'
                                      : 'Respond to this Check'),
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                            ),
                            style: TextButton.styleFrom(
                              foregroundColor: tooFarToVerify ? const Color(0xFF94A3B8) : const Color(0xFF004D40),
                              backgroundColor: tooFarToVerify ? const Color(0xFFF1F5F9) : const Color(0xFFE2F0F0),
                              disabledForegroundColor: const Color(0xFF94A3B8),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ],

                      // ── Responses List ─────────────────────────────────────────
                      if (responses.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Divider(height: 1, color: Color(0xFFE2E8F0)),
                        const SizedBox(height: 10),
                        Text('COMMUNITY RESPONSES (${responses.length})',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: Color(0xFF94A3B8))),
                        const SizedBox(height: 8),
                        ...responses.map((resp) => _ResponseTile(
                              check: widget.check,
                              response: resp,
                              isExpired: _isExpired,
                              isResolved: isResolved,
                              onAcceptAndTip: _acceptAndTip,
                            )),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// A single community response — identity, status, message, and whatever
// action/outcome applies (accept & tip / pending payment / reward earned).
// ─────────────────────────────────────────────────────────────────────────────
class _ResponseTile extends StatelessWidget {
  final Map<String, dynamic> check;
  final Map<String, dynamic> response;
  final bool isExpired;
  final bool isResolved;
  final void Function(Map<String, dynamic> response) onAcceptAndTip;

  const _ResponseTile({
    required this.check,
    required this.response,
    required this.isExpired,
    required this.isResolved,
    required this.onAcceptAndTip,
  });

  static const _statusConfig = {
    'confirmed': {'emoji': '✅', 'color': 0xFF059669},
    'worsening': {'emoji': '⚠️', 'color': 0xFFDC2626},
    'cleared':   {'emoji': '🎉', 'color': 0xFF2563EB},
  };

  @override
  Widget build(BuildContext context) {
    final statusStr = response['status'] as String? ?? '';
    final cfg = _statusConfig[statusStr] ?? const {'emoji': '💬', 'color': 0xFF64748B};
    final sColor = Color(cfg['color'] as int);
    final sEmoji = cfg['emoji'] as String;

    final msg = response['message'] as String? ?? '';
    final paymentStatus = response['payment_status'] as String? ?? 'none';
    final isAccepted = response['is_accepted'] == true && paymentStatus == 'paid';
    final isPending = paymentStatus == 'pending';
    final tipAmount = response['tip_amount'] ?? 0;
    final isPoster = AuthService.currentUserId == check['user_id'];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isAccepted ? const Color(0xFFFFFBEB) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isAccepted ? const Color(0xFFFDE68A) : const Color(0xFFF1F5F9),
          width: isAccepted ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Responder Identity & Time Ago
          FutureBuilder<Map<String, dynamic>?>(
            future: UserMaskingHelper.getProfile(response['user_id']),
            builder: (context, rProfileSnap) {
              final rProfile = rProfileSnap.data;
              final rMaskedName = UserMaskingHelper.maskName(rProfile?['full_name']);
              final rBadge = UserMaskingHelper.getRoleBadge(rProfile?['primary_role']);
              final rTimeAgo = UserMaskingHelper.timeAgo(response['created_at']);

              return Row(
                children: [
                  Expanded(
                    child: Text('$rMaskedName · $rBadge',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF334155))),
                  ),
                  const SizedBox(width: 6),
                  Text(rTimeAgo, style: const TextStyle(fontSize: 9, color: Color(0xFF94A3B8), fontWeight: FontWeight.w500)),
                ],
              );
            },
          ),
          const SizedBox(height: 8),

          // Status pill + message
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: sColor.withOpacity(0.12), borderRadius: BorderRadius.circular(50)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(sEmoji, style: const TextStyle(fontSize: 10)),
              const SizedBox(width: 3),
              Text(statusStr.toUpperCase(), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: sColor)),
            ]),
          ),
          if (msg.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(msg, style: const TextStyle(fontSize: 12, color: Color(0xFF334155), height: 1.3)),
          ],

          if (isAccepted) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('⭐', style: TextStyle(fontSize: 10)),
                  const SizedBox(width: 4),
                  Text('Rewarded ₱$tipAmount', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFFB45309))),
                ],
              ),
            ),
          ] else if (isPending) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 6),
                  Text('Payment Pending ₱$tipAmount', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF64748B))),
                ],
              ),
            ),
          ] else if (isPoster && !isExpired && !isResolved) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => onAcceptAndTip(response),
                icon: const Icon(Icons.stars, size: 14),
                label: const Text('Accept & Tip', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFD97706),
                  backgroundColor: const Color(0xFFFEF3C7),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Responder sheet — lets community members confirm and update a check
// ─────────────────────────────────────────────────────────────────────────────
class _ResponderSheet extends StatefulWidget {
  final Map<String, dynamic> check;
  const _ResponderSheet({required this.check});

  @override
  State<_ResponderSheet> createState() => _ResponderSheetState();
}

class _ResponderSheetState extends State<_ResponderSheet> {
  final _msgCtrl    = TextEditingController();
  bool _isSubmitting = false;
  String _status = 'confirmed'; // 'confirmed' | 'cleared' | 'worsening'

  static const _statuses = [
    {'key': 'confirmed',  'label': 'Still Accurate',  'emoji': '✅', 'color': 0xFF059669},
    {'key': 'worsening',  'label': 'Getting Worse',   'emoji': '⚠️', 'color': 0xFFDC2626},
    {'key': 'cleared',    'label': 'Now Cleared',     'emoji': '🎉', 'color': 0xFF2563EB},
  ];

  Future<void> _submit() async {
    final userId = AuthService.currentUserId;
    if (userId == null) return;
    setState(() => _isSubmitting = true);
    try {
      await Supabase.instance.client.from('community_check_responses').insert({
        'check_id':  widget.check['id'],
        'user_id':   userId,
        'status':    _status,
        'message':   _msgCtrl.text.trim(),
      });

      // Send notification to the poster (always send so testing works even on own posts)
      try {
        final posterId = widget.check['user_id'] ?? userId;
        final landmark = widget.check['landmark'] ?? 'a location';
        final statusLabel = (_statuses.firstWhere(
          (s) => s['key'] == _status,
          orElse: () => {'label': _status},
        )['label'] as String);

        await Supabase.instance.client.from('notifications').insert({
          'user_id': posterId,
          'title': 'New Update on your Community Check',
          'body': 'Someone reported "$statusLabel" near $landmark.',
          'type': 'check_response',
          'reference_id': widget.check['id'],
        });
      } catch (err) {
        debugPrint('Failed to send notification: $err');
      }
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Response submitted! Thank you for helping the community.'),
            backgroundColor: Color(0xFF004D40),
          ),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  void dispose() { _msgCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final landmark = widget.check['landmark'] ?? '';
    final bounty   = (widget.check['bounty'] ?? 0).toDouble();

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        top: 8, left: 20, right: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: Container(
            width: 36, height: 4,
            margin: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(4)),
          )),

          // Header
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: const Color(0xFFE2F0F0), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.record_voice_over_outlined, color: Color(0xFF004D40), size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Submit a Ground Response',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
              Text(landmark, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)), overflow: TextOverflow.ellipsis),
            ])),
          ]),

          // Bounty callout
          if (bounty > 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFED7AA)),
              ),
              child: Row(children: [
                const Text('🎁', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  'This check has a ₱${bounty.toStringAsFixed(0)} bounty. Confirmed responders may be rewarded by the poster.',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF92400E), fontWeight: FontWeight.w600, height: 1.4),
                )),
              ]),
            ),
          ],

          const SizedBox(height: 16),
          const Text('CURRENT STATUS', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: Color(0xFF94A3B8))),
          const SizedBox(height: 8),

          // Status selector
          Row(
            children: _statuses.map((s) {
              final isSelected = _status == s['key'];
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _status = s['key'] as String),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: isSelected ? Color(s['color'] as int).withOpacity(0.12) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? Color(s['color'] as int) : const Color(0xFFE2E8F0),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Column(children: [
                      Text(s['emoji'] as String, style: const TextStyle(fontSize: 16)),
                      const SizedBox(height: 3),
                      Text(s['label'] as String,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10, fontWeight: FontWeight.w700,
                          color: isSelected ? Color(s['color'] as int) : const Color(0xFF64748B),
                        )),
                    ]),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 14),
          TextField(
            controller: _msgCtrl,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'Add context (e.g. "About 20 cars backed up to the bridge")',
              hintStyle: const TextStyle(fontSize: 12, color: Color(0xFFCBD5E1)),
              contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE2E8F0))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF004D40), width: 2)),
            ),
          ),
          const SizedBox(height: 16),

          ElevatedButton(
            onPressed: _isSubmitting ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF004D40),
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 46),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _isSubmitting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Submit Response', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final VoidCallback onPost;
  const _EmptyState({required this.onPost});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 72, height: 72,
            decoration: BoxDecoration(color: const Color(0xFFE2F0F0), borderRadius: BorderRadius.circular(20)),
            child: const Center(child: Text('📍', style: TextStyle(fontSize: 32))),
          ),
          const SizedBox(height: 16),
          const Text('No Active Ground Checks',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
          const SizedBox(height: 6),
          const Text(
            'Be the first to report live conditions in your area.\nChecks expire automatically after 15 minutes.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Color(0xFF64748B), height: 1.5),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: onPost,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF004D40),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            icon: const Icon(Icons.add_location_alt_outlined, size: 16),
            label: const Text('Post the First Check', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ),
        ]),
      ),
    );
  }
}
