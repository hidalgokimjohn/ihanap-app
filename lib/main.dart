import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'screens/role_selection_screen.dart';
import 'screens/seller_screen.dart';
import 'services/auth_service.dart';
import 'services/location_service.dart';
import 'theme/premium_transitions.dart';

final _navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = true;

  await Supabase.initialize(
    url: 'https://fbljufyckedcywiohklc.supabase.co',
    anonKey: 'sb_publishable_LrwNoJHjlZuWXkIxJ5LsuA_Bj_7fBX7',
  );

  final session = Supabase.instance.client.auth.currentSession;
  Widget initialScreen;

  if (session == null) {
    initialScreen = const AuthScreen();
  } else {
    Map<String, dynamic>? profile;

    try {
      profile = await AuthService.getProfile()
          .timeout(const Duration(seconds: 3), onTimeout: () => null);
    } catch (_) {}

    try {
      await LocationService.initializeOnStartup()
          .timeout(const Duration(seconds: 3), onTimeout: () => null);
    } catch (_) {}

    try {
      await Supabase.instance.client
          .from('categories')
          .select()
          .timeout(const Duration(seconds: 2), onTimeout: () => []);
    } catch (_) {}

    final role = profile?['primary_role'];
    if (role == 'responder') {
      initialScreen = const SellerScreen();
    } else if (role == 'buyer') {
      initialScreen = const HomeScreen();
    } else {
      initialScreen = RoleSelectionScreen(
        onRoleSelected: () {
          _navigatorKey.currentState?.pushReplacement(
            MaterialPageRoute(builder: (_) => const HomeScreen()),
          );
        },
      );
    }
  }

  runApp(MyApp(home: initialScreen));
}

class MyApp extends StatelessWidget {
  final Widget home;
  const MyApp({super.key, required this.home});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ping',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: GoogleFonts.plusJakartaSans().fontFamily,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF004D40),
          primary: const Color(0xFF004D40),
          secondary: const Color(0xFFE28743),
          surface: const Color(0xFFF8FAFC),
          onSurface: const Color(0xFF0F172A),
        ),
        textTheme: GoogleFonts.plusJakartaSansTextTheme().copyWith(
          displayLarge:  GoogleFonts.plusJakartaSans(fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: -1.0, height: 1.1,  color: const Color(0xFF0F172A)),
          displayMedium: GoogleFonts.plusJakartaSans(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.8, height: 1.1,  color: const Color(0xFF0F172A)),
          displaySmall:  GoogleFonts.plusJakartaSans(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.4, height: 1.15, color: const Color(0xFF0F172A)),
          headlineLarge:  GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3, height: 1.2, color: const Color(0xFF0F172A)),
          headlineMedium: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: -0.2, height: 1.2, color: const Color(0xFF0F172A)),
          headlineSmall:  GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing:  0,   height: 1.25, color: const Color(0xFF0F172A)),
          titleLarge:  GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0,   height: 1.3, color: const Color(0xFF1E293B)),
          titleMedium: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.1, height: 1.3, color: const Color(0xFF1E293B)),
          titleSmall:  GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.1, height: 1.3, color: const Color(0xFF334155)),
          bodyLarge:  GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w400, letterSpacing: 0, height: 1.45, color: const Color(0xFF334155)),
          bodyMedium: GoogleFonts.plusJakartaSans(fontSize: 12, fontWeight: FontWeight.w400, letterSpacing: 0, height: 1.45, color: const Color(0xFF475569)),
          bodySmall:  GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w400, letterSpacing: 0, height: 1.4,  color: const Color(0xFF64748B)),
          labelLarge:  GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 0.2, height: 1.1, color: const Color(0xFF0F172A)),
          labelMedium: GoogleFonts.plusJakartaSans(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.3, height: 1.1, color: const Color(0xFF334155)),
          labelSmall:  GoogleFonts.plusJakartaSans(fontSize: 10, fontWeight: FontWeight.w600, letterSpacing: 0.5, height: 1.1, color: const Color(0xFF64748B)),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF8FAFC),
          foregroundColor: Color(0xFF0F172A),
          elevation: 0,
          centerTitle: true,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 4,
          shadowColor: Colors.black.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
          ),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        pageTransitionsTheme: premiumPageTransitionsTheme,
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 44),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 0,
          ),
        ),
      ),
      home: home,
    );
  }
}
