import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../screens/community_check_screen.dart';

/// Persistent entry point into the Community Check board — shown in both
/// buyer and merchant app bars since anyone, pinger or responder, can post
/// or answer a ground report regardless of their current mode.
class CommunityCheckShortcut extends StatelessWidget {
  const CommunityCheckShortcut({super.key});

  static const _liveWindow = Duration(minutes: 15);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: Supabase.instance.client
          .from('community_checks')
          .stream(primaryKey: ['id'])
          .order('created_at', ascending: false)
          .limit(50),
      builder: (context, snapshot) {
        int liveCount = 0;
        if (snapshot.hasData) {
          final now = DateTime.now();
          liveCount = snapshot.data!.where((c) {
            final createdAt = DateTime.tryParse(c['created_at']?.toString() ?? '')?.toLocal();
            return createdAt != null && now.difference(createdAt) < _liveWindow;
          }).length;
        }

        final isLive = liveCount > 0;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Tooltip(
            message: 'Community Check',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(50),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CommunityCheckScreen()),
                  );
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: EdgeInsets.symmetric(horizontal: isLive ? 10 : 8, vertical: 7),
                  decoration: BoxDecoration(
                    gradient: isLive
                        ? const LinearGradient(
                            colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: isLive ? null : const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(50),
                    border: isLive ? null : Border.all(color: const Color(0xFFE0E7FF)),
                    boxShadow: isLive
                        ? [
                            BoxShadow(
                              color: const Color(0xFF4F46E5).withValues(alpha: 0.28),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : [],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.location_on_rounded,
                        size: 15,
                        color: isLive ? Colors.white : const Color(0xFF4F46E5),
                      ),
                      if (isLive) ...[
                        const SizedBox(width: 6),
                        const _PulseDot(),
                        const SizedBox(width: 5),
                        Text(
                          '$liveCount Live',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A small breathing dot that signals "this is happening right now" —
/// paired with the live count so the pill reads as active, not static.
class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.35, end: 1.0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut)),
      child: Container(
        width: 6,
        height: 6,
        decoration: const BoxDecoration(color: Color(0xFF4ADE80), shape: BoxShape.circle),
      ),
    );
  }
}
