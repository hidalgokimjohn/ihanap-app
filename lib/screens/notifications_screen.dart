import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../screens/my_requests_screen.dart';
import '../widgets/order_summary_sheet.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
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

  Future<void> _markAsRead(String id) async {
    try {
      await Supabase.instance.client
          .from('notifications')
          .update({'is_read': true})
          .eq('id', id);
    } catch (_) {}
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
            title: const Text('My Requests', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
          ),
          body: const MyRequestsScreen(),
        ),
      ));
      return;
    }

    if (type == 'offer_accepted') {
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
      return;
    }

    if (type == 'check_response' || type == 'tip_received') {
      Navigator.of(context).pop();
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = AuthService.currentUserId;

    if (userId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Notifications')),
        body: const Center(child: Text('Not logged in.')),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Notifications', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: Supabase.instance.client
            .from('notifications')
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

          final notifications = snapshot.data ?? [];

          if (notifications.isEmpty) {
            return Center(
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
                    child: const Icon(Icons.notifications_off_outlined, size: 48, color: Color(0xFF94A3B8)),
                  ),
                  const SizedBox(height: 16),
                  const Text('No notifications yet',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
                  const SizedBox(height: 6),
                  const Text("We'll let you know when there's an update.",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: notifications.length,
            itemBuilder: (context, index) {
              final note = notifications[index];
              final isRead = note['is_read'] == true;
              final type = note['type'] ?? '';
              final title = note['title'] ?? 'Notification';
              final body = note['body'] ?? '';
              
              String iconStr = '🔔';
              Color iconBg = const Color(0xFFF1F5F9);
              if (type == 'new_offer') {
                iconStr = '📩';
                iconBg = const Color(0xFFDBEAFE);
              } else if (type == 'offer_accepted') {
                iconStr = '🎉';
                iconBg = const Color(0xFFD1FAE5);
              } else if (type == 'check_response') {
                iconStr = '💬';
                iconBg = const Color(0xFFFEF3C7);
              } else if (type == 'tip_received') {
                iconStr = '⭐';
                iconBg = const Color(0xFFFEF3C7);
              }

              return GestureDetector(
                onTap: () => _handleTap(note),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isRead ? Colors.white : const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: isRead ? const Color(0xFFE2E8F0) : const Color(0xFFBBF7D0)),
                    boxShadow: isRead ? [] : [
                      BoxShadow(color: const Color(0xFF10B981).withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))
                    ]
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
                        child: Text(iconStr, style: const TextStyle(fontSize: 18)),
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
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: isRead ? FontWeight.w600 : FontWeight.w800,
                                      color: const Color(0xFF0F172A),
                                    ),
                                  ),
                                ),
                                if (!isRead)
                                  Container(
                                    margin: const EdgeInsets.only(left: 8),
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(color: Color(0xFF10B981), shape: BoxShape.circle),
                                  )
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              body,
                              style: TextStyle(
                                fontSize: 13,
                                color: isRead ? const Color(0xFF64748B) : const Color(0xFF475569),
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _timeAgo(note['created_at']),
                              style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8), fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
