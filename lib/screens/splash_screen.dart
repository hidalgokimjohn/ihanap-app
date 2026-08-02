import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import 'auth_screen.dart';
import 'home_screen.dart';
import 'role_selection_screen.dart';
import 'seller_screen.dart';

class LoadingSplashScreen extends StatefulWidget {
  final VoidCallback? onInitializationComplete;

  const LoadingSplashScreen({
    super.key,
    this.onInitializationComplete,
  });

  @override
  State<LoadingSplashScreen> createState() => _LoadingSplashScreenState();
}

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

    // Warm up Location service & disk cache in background
    try {
      await LocationService.initializeOnStartup()
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.onInitializationComplete != null) {
        widget.onInitializationComplete!();
      } else {
        _performSmoothTransition(session, primaryRole);
      }
    });
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
              // ── Minimalist Aesthetic Thunder Logo ───────────────────────────
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF004D40), Color(0xFF00695C)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x28004D40),
                      blurRadius: 24,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.bolt_rounded,
                  color: Colors.white,
                  size: 44,
                ),
              ),

              const SizedBox(height: 24),

              // ── Brand Title with Shader Mask Gradient ──────────────────────
              ShaderMask(
                shaderCallback: (bounds) => const LinearGradient(
                  colors: [Color(0xFF004D40), Color(0xFF10B981)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ).createShader(bounds),
                child: Text(
                  'Ping',
                  style: GoogleFonts.outfit(
                    fontSize: 40,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1.2,
                    color: Colors.white,
                  ),
                ),
              ),

              const SizedBox(height: 8),

              Text(
                'Broadcast to local shops in seconds.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF64748B),
                ),
              ),

              const SizedBox(height: 48),

              // ── Modern Animated Progress Indicator ───────────────────────
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Color(0xFF004D40),
                  strokeWidth: 2.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
