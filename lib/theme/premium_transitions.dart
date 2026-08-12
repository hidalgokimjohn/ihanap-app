import 'package:flutter/material.dart';

/// App-wide page transition: a soft fade combined with a subtle upward
/// slide, eased with easeOutCubic. Applied once via [ThemeData.pageTransitionsTheme]
/// so every `Navigator.push(MaterialPageRoute(...))` in the app inherits it
/// automatically — no per-screen wiring needed.
class PremiumPageTransitionsBuilder extends PageTransitionsBuilder {
  const PremiumPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final entering = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    return FadeTransition(
      opacity: entering,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.035),
          end: Offset.zero,
        ).animate(entering),
        child: child,
      ),
    );
  }
}

/// Drop-in replacement for [ThemeData.pageTransitionsTheme] that applies the
/// same premium transition across every platform, so behavior is identical
/// whether the app is running on web, Android, or iOS.
const premiumPageTransitionsTheme = PageTransitionsTheme(
  builders: {
    TargetPlatform.android: PremiumPageTransitionsBuilder(),
    TargetPlatform.iOS: PremiumPageTransitionsBuilder(),
    TargetPlatform.macOS: PremiumPageTransitionsBuilder(),
    TargetPlatform.windows: PremiumPageTransitionsBuilder(),
    TargetPlatform.linux: PremiumPageTransitionsBuilder(),
    TargetPlatform.fuchsia: PremiumPageTransitionsBuilder(),
  },
);
