import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'location_service.dart';

/// Service that queries nearby shops within a given radius of the user's location.
/// Uses client-side Haversine filtering since PostGIS is not required.
class NearbyShopsService {
  static List<Map<String, dynamic>>? _cachedShops;
  static DateTime? _cacheTime;
  static const _cacheDuration = Duration(seconds: 60);

  // Category emoji lookup for UI
  static String typeEmoji(String? type) {
    switch (type) {
      case 'auto_parts': return '🚗';
      case 'hardware':   return '🔧';
      case 'rooms':      return '🏠';
      case 'rider':      return '📦';
      case 'food':       return '🍽️';
      case 'repair':     return '🛠️';
      case 'community':  return '📍';
      default:           return '🏪';
    }
  }

  /// Fetches all shops that have GPS coordinates and filters by [radiusKm].
  ///
  /// Returns a list of shop rows within radius — or an empty list if:
  /// - User location is unavailable
  /// - Supabase query fails
  static Future<List<Map<String, dynamic>>> fetchNearbyShops({
    double radiusKm = 5.0,
  }) async {
    final loc = LocationService.currentLocationNotifier.value;
    if (loc == null) return [];

    // Return cached result if fresh
    if (_cachedShops != null && _cacheTime != null) {
      if (DateTime.now().difference(_cacheTime!) < _cacheDuration) {
        return _filterByRadius(_cachedShops!, loc.latitude, loc.longitude, radiusKm);
      }
    }

    try {
      final data = await Supabase.instance.client
          .from('responders')
          .select('id, shop_name, responder_type, city_name, latitude, longitude, description')
          .not('latitude', 'is', null)
          .not('longitude', 'is', null)
          .timeout(const Duration(seconds: 8));

      _cachedShops = List<Map<String, dynamic>>.from(data);
      _cacheTime = DateTime.now();

      return _filterByRadius(_cachedShops!, loc.latitude, loc.longitude, radiusKm);
    } catch (e) {
      debugPrint('[NearbyShops] fetch error: $e');
      // Return from stale cache if available, filtered
      if (_cachedShops != null) {
        return _filterByRadius(_cachedShops!, loc.latitude, loc.longitude, radiusKm);
      }
      return [];
    }
  }

  static List<Map<String, dynamic>> _filterByRadius(
    List<Map<String, dynamic>> shops,
    double userLat,
    double userLng,
    double radiusKm,
  ) {
    return shops.where((shop) {
      final lat = (shop['latitude'] as num?)?.toDouble();
      final lng = (shop['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) return false;
      final dist = LocationService.calculateDistanceKm(userLat, userLng, lat, lng);
      return dist <= radiusKm;
    }).toList();
  }

  /// Invalidate the cache (e.g. after a location update)
  static void invalidateCache() {
    _cachedShops = null;
    _cacheTime = null;
  }
}
