import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  /// Returns current authenticated user
  static User? get currentUser => _supabase.auth.currentUser;

  /// Returns current auth user ID
  static String? get currentUserId => currentUser?.id;

  /// Stream of Auth State changes
  static Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

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
      // Upsert base profile record
      await _supabase.from('profiles').upsert({
        'id': user.id,
        'email': email,
        'full_name': fullName,
        'primary_role': role,
        if (contactNumber != null && contactNumber.isNotEmpty) 'contact_number': contactNumber,
        if (barangay != null && barangay.isNotEmpty) 'barangay': barangay,
      });

      if (role == 'responder' && shopName != null && responderType != null) {
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
      }
    }

    return response;
  }

  /// Sign In with Email & Password
  static Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  /// Sign In with Google
  static Future<void> signInWithGoogle() async {
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

  /// Sign Out
  static Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  /// Fetch user profile by ID or current user
  static Future<Map<String, dynamic>?> getProfile([String? userId]) async {
    final uid = userId ?? currentUserId;
    if (uid == null) return null;

    try {
      var data = await _supabase
          .from('profiles')
          .select()
          .eq('id', uid)
          .maybeSingle();
      
      // If no profile exists (e.g. fresh Google OAuth login), create it now
      if (data == null) {
        await ensureProfileExists();
        data = await _supabase
            .from('profiles')
            .select()
            .eq('id', uid)
            .maybeSingle();
      }
      
      return data;
    } catch (e) {
      debugPrint('Error fetching profile: $e');
      return null;
    }
  }

  /// Update user profile
  static Future<void> updateProfile(Map<String, dynamic> updates) async {
    final uid = currentUserId;
    if (uid == null) return;

    await _supabase.from('profiles').update(updates).eq('id', uid);
  }
}
