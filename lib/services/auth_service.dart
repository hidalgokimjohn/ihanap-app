import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Optimized Authentication & Profile Service with In-Memory Caching
class AuthService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  // Memory Cache for User Profile to eliminate redundant Supabase network calls
  static Map<String, dynamic>? _cachedProfile;
  static String? _cachedUserId;

  /// Returns current authenticated user
  static User? get currentUser => _supabase.auth.currentUser;

  /// Returns current auth user ID
  static String? get currentUserId => currentUser?.id;

  /// Stream of Auth State changes
  static Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  /// Clear in-memory cache
  static void clearCache() {
    _cachedProfile = null;
    _cachedUserId = null;
  }

  /// Sign Up with Email & Password and create Profile entry
  static Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String fullName,
    required String role,
    String? contactNumber,
    String? barangay,
    String? shopName,
    String? responderType,
    String? tagline,
  }) async {
    final response = await _supabase.auth.signUp(
      email: email,
      password: password,
      data: {'full_name': fullName},
    );

    final user = response.user;
    if (user != null) {
      // If sign up didn't automatically establish an active session, attempt immediate sign-in
      if (response.session == null) {
        try {
          await _supabase.auth.signInWithPassword(email: email, password: password);
        } catch (e) {
          debugPrint('Auto sign-in after signup skipped or failed: $e');
        }
      }

      final profileData = {
        'id': user.id,
        'email': email,
        'full_name': fullName,
        'primary_role': role,
        if (contactNumber != null && contactNumber.isNotEmpty) 'contact_number': contactNumber,
        if (barangay != null && barangay.isNotEmpty) 'barangay': barangay,
      };

      // Upsert base profile record
      try {
        await _supabase.from('profiles').upsert(profileData);
      } catch (e) {
        debugPrint('Profile upsert error during signup: $e');
      }
      _cachedProfile = profileData;
      _cachedUserId = user.id;

      if (role == 'responder' && shopName != null && responderType != null) {
        try {
          final responderResponse = await _supabase.from('responders').insert({
            'profile_id': user.id,
            'shop_name': shopName,
            'owner_name': fullName,
            'responder_type': responderType,
            if (contactNumber != null && contactNumber.isNotEmpty) 'contact_number': contactNumber,
            if (tagline != null && tagline.isNotEmpty) 'description': tagline,
            'city_name': 'Butuan City',
          }).select().single();

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('active_shop_id', responderResponse['id']);
          await prefs.setString('responder_shop_name', shopName);
          await prefs.setString('responder_type', responderType);
          await prefs.setString('responder_owner_name', fullName);
        } catch (e) {
          debugPrint('Responder insert error during signup: $e');
        }
      }
    }

    return response;
  }

  /// Sign In with Email & Password
  static Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    clearCache();
    return await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  /// Sign In with Google
  static Future<void> signInWithGoogle() async {
    clearCache();
    final String? redirectTo = kIsWeb ? Uri.base.origin : null;

    await _supabase.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: redirectTo,
    );
  }

  /// Ensure a profile exists for the user (mostly for OAuth signups)
  static Future<void> ensureProfileExists() async {
    final user = currentUser;
    if (user == null) return;

    final name = user.userMetadata?['full_name'] ?? user.userMetadata?['name'] ?? 'User';

    try {
      await _supabase.from('profiles').upsert({
        'id': user.id,
        'email': user.email ?? '',
        'full_name': name,
      });
    } catch (e) {
      debugPrint('Error creating Google profile: $e');
    }
  }

  /// Sign Out and reset local state
  static Future<void> signOut() async {
    clearCache();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (e) {
      debugPrint('Error clearing SharedPreferences: $e');
    }
    try {
      await _supabase.auth.signOut();
    } catch (e) {
      debugPrint('Error signing out of Supabase: $e');
    }
  }

  /// Fetch user profile by ID or current user with Memory Caching & Timeout
  static Future<Map<String, dynamic>?> getProfile([String? userId, bool forceRefresh = false]) async {
    final uid = userId ?? currentUserId;
    if (uid == null) return null;

    // Return cached profile if available and not forced to refresh
    if (!forceRefresh && _cachedUserId == uid && _cachedProfile != null) {
      return _cachedProfile;
    }

    try {
      var data = await _supabase
          .from('profiles')
          .select()
          .eq('id', uid)
          .maybeSingle()
          .timeout(const Duration(seconds: 4), onTimeout: () => null);

      // If no profile exists (e.g. fresh Google OAuth login), create it now
      if (data == null) {
        await ensureProfileExists();
        data = await _supabase
            .from('profiles')
            .select()
            .eq('id', uid)
            .maybeSingle()
            .timeout(const Duration(seconds: 3), onTimeout: () => null);
      }

      if (data != null) {
        _cachedProfile = data;
        _cachedUserId = uid;
      }

      return data;
    } catch (e) {
      debugPrint('Error fetching profile: $e');
      return _cachedProfile;
    }
  }

  /// Update user profile and update local cache immediately
  static Future<void> updateProfile(Map<String, dynamic> updates) async {
    final uid = currentUserId;
    if (uid == null) return;

    await _supabase.from('profiles').update(updates).eq('id', uid);

    if (_cachedProfile != null && _cachedUserId == uid) {
      _cachedProfile!.addAll(updates);
    }
  }
}
