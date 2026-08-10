import 'package:flutter/material.dart';

/// Primary CTA button with three "premium" touches layered on top of a
/// normal Material button: a tactile press-scale, a smooth color/shadow
/// transition when enabled/disabled changes, and a crossfade (rather than a
/// hard swap) between the label and the loading spinner.
class PremiumButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final bool isLoading;
  final Widget child;
  final Gradient? gradient;
  final Color? color;
  final double height;
  final BorderRadius? borderRadius;
  final List<BoxShadow>? boxShadow;
  final EdgeInsetsGeometry padding;

  const PremiumButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.isLoading = false,
    this.gradient,
    this.color,
    this.height = 54,
    this.borderRadius,
    this.boxShadow,
    this.padding = const EdgeInsets.symmetric(horizontal: 24),
  });

  @override
  State<PremiumButton> createState() => _PremiumButtonState();
}

class _PremiumButtonState extends State<PremiumButton> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null && !widget.isLoading;

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? BorderRadius.circular(16);

    return AnimatedScale(
      scale: _pressed ? 0.97 : 1.0,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        height: widget.height,
        decoration: BoxDecoration(
          gradient: _enabled ? widget.gradient : null,
          color: _enabled ? (widget.gradient == null ? (widget.color ?? const Color(0xFF004D40)) : null) : const Color(0xFFCBD5E1),
          borderRadius: radius,
          boxShadow: _enabled ? (widget.boxShadow ?? const []) : const [],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            borderRadius: radius,
            onTap: _enabled ? widget.onPressed : null,
            onHighlightChanged: (v) {
              if (mounted) setState(() => _pressed = v);
            },
            child: Padding(
              padding: widget.padding,
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: ScaleTransition(scale: Tween(begin: 0.9, end: 1.0).animate(anim), child: child),
                  ),
                  child: widget.isLoading
                      ? const SizedBox(
                          key: ValueKey('loading'),
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.4),
                        )
                      : KeyedSubtree(key: const ValueKey('label'), child: widget.child),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
