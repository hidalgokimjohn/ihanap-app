import 'package:flutter/material.dart';
import '../services/location_service.dart';
import '../services/nearby_shops_service.dart';

/// Reactive banner displayed on the requester home screen showing how many
/// shops are active within 5 km of the user's current GPS location.
class NearbyShopsBanner extends StatefulWidget {
  const NearbyShopsBanner({super.key});

  @override
  State<NearbyShopsBanner> createState() => _NearbyShopsBannerState();
}

class _NearbyShopsBannerState extends State<NearbyShopsBanner>
    with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>>? _shops;
  bool _isLoading = true;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    LocationService.currentLocationNotifier.addListener(_onLocationChanged);
    _fetchShops();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    LocationService.currentLocationNotifier.removeListener(_onLocationChanged);
    super.dispose();
  }

  void _onLocationChanged() {
    NearbyShopsService.invalidateCache();
    _fetchShops();
  }

  Future<void> _fetchShops() async {
    if (!mounted) return;
    // Only show loading state on first fetch
    if (_shops == null) setState(() => _isLoading = true);
    final shops = await NearbyShopsService.fetchNearbyShops(radiusKm: 5.0);
    if (mounted) {
      setState(() {
        _shops = shops;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = LocationService.currentLocationNotifier.value;

    // Hide if location is unavailable and we have no data
    if (loc == null && _shops == null) return const SizedBox.shrink();

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      child: _isLoading && _shops == null
          ? _buildShimmer()
          : _buildBanner(),
    );
  }

  Widget _buildBanner() {
    final count = _shops?.length ?? 0;
    final loc = LocationService.currentLocationNotifier.value;

    return Container(
      key: ValueKey(count),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: count > 0 ? const Color(0xFFD1FAE5) : const Color(0xFFE2E8F0),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          // Pulsing dot indicator
          SizedBox(
            width: 20,
            height: 20,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedBuilder(
                  animation: _pulseAnim,
                  builder: (_, __) => Container(
                    width: 16 * _pulseAnim.value,
                    height: 16 * _pulseAnim.value,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: count > 0
                          ? const Color(0xFF10B981).withValues(alpha: 0.25 * _pulseAnim.value)
                          : const Color(0xFF94A3B8).withValues(alpha: 0.2 * _pulseAnim.value),
                    ),
                  ),
                ),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: count > 0 ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),

          // Main text
          Expanded(
            child: count > 0
                ? RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        fontFamily: 'PlusJakartaSans',
                        fontSize: 12,
                        color: Color(0xFF334155),
                        height: 1.3,
                      ),
                      children: [
                        TextSpan(
                          text: '$count ${count == 1 ? 'shop' : 'shops'} ',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF004D40),
                          ),
                        ),
                        const TextSpan(text: 'in your area — ready to respond to your Ping'),
                      ],
                    ),
                  )
                : Text(
                    loc == null
                        ? 'Enable location to see nearby shops'
                        : 'No shops nearby yet',
                    style: const TextStyle(
                      fontFamily: 'PlusJakartaSans',
                      fontSize: 12,
                      color: Color(0xFF94A3B8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
          ),

          const SizedBox(width: 8),

          // Shop category preview icons (up to 4)
          if (count > 0)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: _shops!
                  .take(4)
                  .map((s) => Padding(
                        padding: const EdgeInsets.only(left: 2),
                        child: Text(
                          NearbyShopsService.typeEmoji(s['responder_type'] as String?),
                          style: const TextStyle(fontSize: 13),
                        ),
                      ))
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildShimmer() {
    return Container(
      key: const ValueKey('shimmer'),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      height: 44,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }
}
