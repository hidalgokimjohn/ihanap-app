import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../screens/my_requests_screen.dart';
import '../screens/community_check_screen.dart';
import '../widgets/order_summary_sheet.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  StreamSubscription<List<Map<String, dynamic>>>? _sub;
  List<Map<String, dynamic>> _notifications = [];
  bool _loading = true;

  Timer? _debounce;
  List<Map<String, dynamic>>? _pendingSnapshot;

  final Set<String> _dismissedIds = {};
  String _filter = 'all'; // 'all' | 'unread'

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  void _subscribe() {
    final userId = AuthService.currentUserId;
    if (userId == null) return;
    _sub = Supabase.instance.client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .listen(_onSnapshot);
  }

  void _onSnapshot(List<Map<String, dynamic>> data) {
    _pendingSnapshot = data;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      final incoming = _pendingSnapshot;
      if (incoming == null) return;
      setState(() {
        _notifications = incoming;
        _loading = false;
      });
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _sub?.cancel();
    super.dispose();
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

  String _dateGroup(String? iso) {
    final dt = DateTime.tryParse(iso ?? '')?.toLocal();
    if (dt == null) return 'Earlier';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final d = DateTime(dt.year, dt.month, dt.day);
    if (d == today) return 'Today';
    if (d == yesterday) return 'Yesterday';
    return 'Earlier';
  }

  Future<void> _markAsRead(String id) async {
    try {
      await Supabase.instance.client
          .from('notifications')
          .update({'is_read': true})
          .eq('id', id);
    } catch (_) {}
  }

  Future<void> _markAllAsRead() async {
    final userId = AuthService.currentUserId;
    if (userId == null) return;
    try {
      await Supabase.instance.client
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', userId)
          .eq('is_read', false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not mark all as read: $e'), backgroundColor: const Color(0xFFEF4444)),
        );
      }
    }
  }

  Future<void> _deleteNotification(String id) async {
    try {
      await Supabase.instance.client.from('notifications').delete().eq('id', id);
    } catch (e) {
      if (mounted) {
        setState(() => _dismissedIds.remove(id));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete: $e'), backgroundColor: const Color(0xFFEF4444)),
        );
      }
    }
  }

  Future<void> _openOrderSummary(dynamic referenceId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator(color: Color(0xFF004D40))),
    );

    try {
      final request = await Supabase.instance.client
          .from('requests')
          .select()
          .eq('id', referenceId)
          .maybeSingle();

      if (mounted) Navigator.pop(context);

      if (request == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request not found.')));
        return;
      }

      if (mounted) {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (_) => OrderSummarySheet(request: request),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _handleTap(Map<String, dynamic> note) async {
    final isRead = note['is_read'] == true;
    if (!isRead) _markAsRead(note['id']);

    final referenceId = note['reference_id'];
    if (referenceId == null) return;

    final type = note['type'];

    if (type == 'new_offer') {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: Text('My Pings', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 18, color: const Color(0xFF0F172A))),
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
          ),
          body: const MyRequestsScreen(),
        ),
      ));
      return;
    }

    if (type == 'offer_accepted' || type == 'order_ready' || type == 'order_completed') {
      await _openOrderSummary(referenceId);
      return;
    }

    if (type == 'check_response' || type == 'tip_received') {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CommunityCheckScreen()));
      return;
    }
  }

  ({IconData icon, Color bg, Color fg}) _iconFor(String type) {
    switch (type) {
      case 'new_offer':
        return (icon: Icons.local_offer_rounded, bg: const Color(0xFFDBEAFE), fg: const Color(0xFF2563EB));
      case 'offer_accepted':
        return (icon: Icons.celebration_rounded, bg: const Color(0xFFD1FAE5), fg: const Color(0xFF059669));
      case 'order_ready':
        return (icon: Icons.local_shipping_rounded, bg: const Color(0xFFFFF7ED), fg: const Color(0xFFEA580C));
      case 'order_completed':
        return (icon: Icons.task_alt_rounded, bg: const Color(0xFFDCFCE7), fg: const Color(0xFF15803D));
      case 'check_response':
        return (icon: Icons.chat_bubble_rounded, bg: const Color(0xFFFEF3C7), fg: const Color(0xFFB45309));
      case 'tip_received':
        return (icon: Icons.star_rounded, bg: const Color(0xFFFEF3C7), fg: const Color(0xFFD97706));
      default:
        return (icon: Icons.notifications_rounded, bg: const Color(0xFFF1F5F9), fg: const Color(0xFF64748B));
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = AuthService.currentUserId;

    if (userId == null) {
      return Scaffold(
        appBar: AppBar(title: Text('Notifications', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800))),
        body: const Center(child: Text('Not logged in.')),
      );
    }

    if (_loading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: _buildAppBar(hasUnread: false),
        body: const Center(child: CircularProgressIndicator(color: Color(0xFF004D40))),
      );
    }

    // Strip locally-dismissed items optimistically.
    final allNotes = _notifications.where((n) => !_dismissedIds.contains(n['id'].toString())).toList();
    final unreadCount = allNotes.where((n) => n['is_read'] != true).length;
    final visible = _filter == 'unread' ? allNotes.where((n) => n['is_read'] != true).toList() : allNotes;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: _buildAppBar(hasUnread: unreadCount > 0),
      body: Column(
        children: [
          // ── Filter tabs ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                _FilterTab(
                  label: 'All',
                  count: allNotes.length,
                  selected: _filter == 'all',
                  onTap: () => setState(() => _filter = 'all'),
                ),
                const SizedBox(width: 8),
                _FilterTab(
                  label: 'Unread',
                  count: unreadCount,
                  selected: _filter == 'unread',
                  onTap: () => setState(() => _filter = 'unread'),
                  badge: unreadCount > 0,
                ),
              ],
            ),
          ),

          Expanded(
            child: visible.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Icon(
                            _filter == 'unread' ? Icons.mark_email_read_rounded : Icons.notifications_off_rounded,
                            size: 48,
                            color: const Color(0xFF94A3B8),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _filter == 'unread' ? "You're all caught up" : 'No notifications yet',
                          style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _filter == 'unread' ? 'No unread notifications right now.' : "We'll let you know when there's an update.",
                          textAlign: TextAlign.center,
                          style: GoogleFonts.plusJakartaSans(fontSize: 13, color: const Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    children: _buildGroupedList(visible),
                  ),
          ),
        ],
      ),
    );
  }

  AppBar _buildAppBar({required bool hasUnread}) {
    return AppBar(
      title: Text('Notifications', style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w800, fontSize: 18, color: const Color(0xFF0F172A))),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 0,
      actions: [
        if (hasUnread)
          TextButton(
            onPressed: _markAllAsRead,
            child: Text('Mark all read', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF004D40))),
          ),
        const SizedBox(width: 4),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(color: const Color(0xFFE2E8F0), height: 1),
      ),
    );
  }

  List<Widget> _buildGroupedList(List<Map<String, dynamic>> notes) {
    final widgets = <Widget>[];
    String? lastGroup;

    for (final note in notes) {
      final group = _dateGroup(note['created_at']);
      if (group != lastGroup) {
        if (lastGroup != null) widgets.add(const SizedBox(height: 4));
        widgets.add(Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
          child: Text(
            group.toUpperCase(),
            style: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w800, color: const Color(0xFF94A3B8), letterSpacing: 0.6),
          ),
        ));
        lastGroup = group;
      }
      widgets.add(_buildNotificationCard(note));
    }

    return widgets;
  }

  Widget _buildNotificationCard(Map<String, dynamic> note) {
    final id = note['id'].toString();
    final isRead = note['is_read'] == true;
    final type = (note['type'] ?? '').toString();
    final title = note['title'] ?? 'Notification';
    final body = note['body'] ?? '';
    final iconSpec = _iconFor(type);

    return Dismissible(
      key: Key('notif_$id'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) {
        setState(() => _dismissedIds.add(id));
        _deleteNotification(id);
      },
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.only(right: 20),
        alignment: Alignment.centerRight,
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFFCA5A5)),
        ),
        child: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 22),
      ),
      child: GestureDetector(
        onTap: () => _handleTap(note),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isRead ? Colors.white : const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: isRead ? const Color(0xFFE2E8F0) : const Color(0xFFBBF7D0)),
            boxShadow: isRead
                ? []
                : [BoxShadow(color: const Color(0xFF10B981).withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 4))],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: iconSpec.bg, shape: BoxShape.circle),
                child: Icon(iconSpec.icon, size: 20, color: iconSpec.fg),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: GoogleFonts.outfit(
                              fontSize: 15,
                              fontWeight: isRead ? FontWeight.w600 : FontWeight.w800,
                              color: const Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        if (!isRead)
                          Container(
                            margin: const EdgeInsets.only(left: 8, top: 4),
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: isRead ? const Color(0xFF64748B) : const Color(0xFF475569),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _timeAgo(note['created_at']),
                      style: GoogleFonts.plusJakartaSans(fontSize: 11, color: const Color(0xFF94A3B8), fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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
          border: Border.all(color: selected ? const Color(0xFF004D40) : const Color(0xFFE2E8F0)),
          boxShadow: selected
              ? [BoxShadow(color: const Color(0xFF004D40).withValues(alpha: 0.18), blurRadius: 8, offset: const Offset(0, 3))]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
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
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: selected ? Colors.white : (badge ? Colors.white : const Color(0xFF64748B)),
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
