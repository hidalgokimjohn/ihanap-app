import 'package:supabase_flutter/supabase_flutter.dart';

class UserMaskingHelper {
  /// Masks a full name into "Firstname ***" format (e.g. "Kim John Hidalgo" -> "Kim ***")
  static String maskName(String? fullName) {
    if (fullName == null || fullName.trim().isEmpty) {
      return 'Member ***';
    }
    final parts = fullName.trim().split(RegExp(r'\s+'));
    final firstName = parts.first;
    if (firstName.isEmpty) return 'Member ***';
    
    // Capitalize first letter of firstname
    final formattedFirstName = firstName[0].toUpperCase() + (firstName.length > 1 ? firstName.substring(1).toLowerCase() : '');
    return '$formattedFirstName ***';
  }

  /// Calculates relative time string (e.g. "just now", "5m ago", "2h ago", "1d ago")
  static String timeAgo(dynamic isoOrDateTime) {
    if (isoOrDateTime == null) return '';
    DateTime? dt;
    if (isoOrDateTime is DateTime) {
      dt = isoOrDateTime;
    } else if (isoOrDateTime is String) {
      dt = DateTime.tryParse(isoOrDateTime);
    }
    if (dt == null) return '';

    final diff = DateTime.now().difference(dt.toLocal());
    if (diff.inSeconds < 30) return 'just now';
    if (diff.inMinutes < 1) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  /// Fetches profile information for a given user_id with caching capability
  static final Map<String, Map<String, dynamic>> _profileCache = {};

  static Future<Map<String, dynamic>?> getProfile(String? userId) async {
    if (userId == null || userId.isEmpty) return null;
    if (_profileCache.containsKey(userId)) {
      return _profileCache[userId];
    }

    try {
      final res = await Supabase.instance.client
          .from('profiles')
          .select('full_name, primary_role')
          .eq('id', userId)
          .maybeSingle();

      if (res != null) {
        _profileCache[userId] = res;
      }
      return res;
    } catch (_) {
      return null;
    }
  }

  /// Formats badge title based on profile role
  static String getRoleBadge(String? role) {
    if (role == 'responder') return 'Local Responder';
    if (role == 'seller') return 'Verified Seller';
    return 'Community Member';
  }
}
