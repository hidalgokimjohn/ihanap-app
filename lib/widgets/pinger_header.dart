import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/user_masking_helper.dart';

/// Leads every Ping card with "who's asking" — the way marketplace listings
/// (Facebook Marketplace, Carousell, OLX) always put the poster identity
/// first, before the content of the listing itself. Full identity stays
/// masked until the request is actually matched (see OrderSummarySheet).
///
/// Each requester also gets a deterministic avatar color derived from their
/// user id, so a merchant scrolling a busy feed can visually recognize a
/// repeat requester at a glance without re-reading the name every time.
class PingerHeader extends StatelessWidget {
  final String? userId;
  final String? createdAt;
  final Widget? trailing;

  const PingerHeader({
    super.key,
    required this.userId,
    this.createdAt,
    this.trailing,
  });

  static const List<(Color, Color)> _palette = [
    (Color(0xFFE0E7FF), Color(0xFF4F46E5)),
    (Color(0xFFFCE7F3), Color(0xFFDB2777)),
    (Color(0xFFDCFCE7), Color(0xFF16A34A)),
    (Color(0xFFFEF3C7), Color(0xFFB45309)),
    (Color(0xFFE0F2FE), Color(0xFF0284C7)),
    (Color(0xFFF3E8FF), Color(0xFF9333EA)),
  ];

  (Color, Color) _colorsFor(String seed) {
    final hash = seed.codeUnits.fold<int>(0, (a, b) => a + b);
    return _palette[hash % _palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final id = userId ?? '';
    return FutureBuilder<Map<String, dynamic>?>(
      future: id.isEmpty ? null : UserMaskingHelper.getProfile(id),
      builder: (context, snap) {
        final maskedName = UserMaskingHelper.maskName(snap.data?['full_name'] as String?);
        final initial = maskedName.isNotEmpty ? maskedName[0].toUpperCase() : '?';
        final colors = _colorsFor(id.isEmpty ? maskedName : id);
        final timeAgo = createdAt != null ? UserMaskingHelper.timeAgo(createdAt) : '';

        return Row(
          children: [
            CircleAvatar(
              radius: 15,
              backgroundColor: colors.$1,
              child: Text(initial, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: colors.$2)),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    maskedName,
                    style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w800, color: const Color(0xFF0F172A)),
                  ),
                  if (timeAgo.isNotEmpty)
                    Text(
                      timeAgo,
                      style: GoogleFonts.plusJakartaSans(fontSize: 10.5, fontWeight: FontWeight.w500, color: const Color(0xFF94A3B8)),
                    ),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        );
      },
    );
  }
}
