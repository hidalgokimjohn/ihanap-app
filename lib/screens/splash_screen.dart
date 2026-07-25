import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import 'auth_screen.dart';
import 'home_screen.dart';
import 'role_selection_screen.dart';
import 'seller_screen.dart';

/// Simple, Aesthetic, Minimalist Loading Screen for Ping Startup
class LoadingSplashScreen extends StatefulWidget {
  final VoidCallback? onInitializationComplete;
  final String? initialStatus;

  const LoadingSplashScreen({
    super.key,
    this.onInitializationComplete,
    this.initialStatus,
  });

  @override
  State<LoadingSplashScreen> createState() => _LoadingSplashScreenState();
}

// Backward compatibility alias
typedef SplashScreen = LoadingSplashScreen;

class _LoadingSplashScreenState extends State<LoadingSplashScreen> {
  bool _isNavigating = false;

  @override
  void initState() {
    super.initState();
    _executeAppInitialization();
  }

  /// App Startup Initialization Pipeline
  Future<void> _executeAppInitialization() async {
    final session = Supabase.instance.client.auth.currentSession;
    Map<String, dynamic>? profile;
    String? primaryRole;

    if (session != null) {
      try {
        profile = await AuthService.getProfile()
            .timeout(const Duration(seconds: 3), onTimeout: () => null);
        primaryRole = profile?['primary_role'];
      } catch (e) {
        debugPrint('Auth profile error during startup: $e');
      }
    }

    if (!mounted) return;

    // Check Location permissions in background
    try {
      await LocationService.getCurrentPosition()
          .timeout(const Duration(seconds: 3), onTimeout: () => null);
    } catch (e) {
      debugPrint('Location service error during startup: $e');
    }

    if (!mounted) return;

    // Preload categories in background
    try {
      await Supabase.instance.client
          .from('categories')
          .select()
          .timeout(const Duration(seconds: 2), onTimeout: () => []);
    } catch (e) {
      debugPrint('Category preload error during startup: $e');
    }

    if (!mounted) return;

    if (_isNavigating) return;
    _isNavigating = true;

    if (widget.onInitializationComplete != null) {
      widget.onInitializationComplete!();
    } else {
      _performSmoothTransition(session, primaryRole);
    }
  }

  /// Smooth PageRouteBuilder fade transition to destination screen
  void _performSmoothTransition(Session? session, String? role) {
    Widget targetScreen;

    if (session == null) {
      targetScreen = const AuthScreen();
    } else if (role == 'responder') {
      targetScreen = const SellerScreen();
    } else if (role == 'buyer') {
      targetScreen = const HomeScreen();
    } else {
      targetScreen = RoleSelectionScreen(
        onRoleSelected: () {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        },
      );
    }

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => targetScreen,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOut,
            ),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // ── Minimalist Aesthetic Logo ───────────────────────────
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFF004D40),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF004D40).withValues(alpha: 0.18),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.bolt_rounded,
                  color: Colors.white,
                  size: 40,
                ),
              ),

              const SizedBox(height: 24),

              // ── Brand Title ──────────────────────────────────────────
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Ping',
                    style: GoogleFonts.outfit(
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1.0,
                      color: const Color(0xFF0F172A),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.only(left: 4, top: 12),
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE28743),
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 6),

              Text(
                'Broadcast to local shops in seconds.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF64748B),
                ),
              ),

              const SizedBox(height: 36),

              // ── Simple Aesthetic Loader ──────────────────────────────
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF004D40)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
