import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

/// Optimized Location Service with Battery-Saving GPS Caching & Nominatim Throttling
class LocationService {
  static Position? _cachedPosition;
  static DateTime? _lastGPSFetchTime;
  static final Map<String, Map<String, String>> _geocodeCache = {};

  /// Check permission and get user's current GPS position with caching
  static Future<Position?> getCurrentPosition({bool forceRefresh = false}) async {
    // Return cached position if fetched within the last 30 seconds
    if (!forceRefresh && _cachedPosition != null && _lastGPSFetchTime != null) {
      if (DateTime.now().difference(_lastGPSFetchTime!) < const Duration(seconds: 30)) {
        return _cachedPosition;
      }
    }

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Location services are disabled.');
        return _cachedPosition;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('Location permissions are denied');
          return _cachedPosition;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('Location permissions are permanently denied.');
        return _cachedPosition;
      }

      // Try fast last known position first if available
      Position? position = await Geolocator.getLastKnownPosition();
      if (position != null && !forceRefresh) {
        _cachedPosition = position;
        _lastGPSFetchTime = DateTime.now();
        return position;
      }

      // Fetch fresh position with 5-second safety timeout
      position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 5),
      );

      _cachedPosition = position;
      _lastGPSFetchTime = DateTime.now();
      return position;
    } catch (e) {
      debugPrint('Error getting current position: $e');
      return _cachedPosition;
    }
  }

  /// Reverse geocode coordinates to City & Barangay with caching
  static Future<Map<String, String>> getCityAndBarangay(double lat, double lng) async {
    final cacheKey = '${lat.toStringAsFixed(3)}_${lng.toStringAsFixed(3)}';
    if (_geocodeCache.containsKey(cacheKey)) {
      return _geocodeCache[cacheKey]!;
    }

    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=$lat&lon=$lng',
      );
      final response = await http.get(
        url,
        headers: {'User-Agent': 'PingApp/1.0 (contact@ping.ph)'},
      ).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final address = data['address'] as Map<String, dynamic>?;

        if (address != null) {
          final city = address['city'] ??
              address['municipality'] ??
              address['town'] ??
              address['county'] ??
              'Butuan City';
          final barangay = address['quarter'] ??
              address['suburb'] ??
              address['village'] ??
              address['neighbourhood'] ??
              address['hamlet'] ??
              'Downtown';

          final result = {
            'city': city.toString(),
            'barangay': barangay.toString(),
          };

          _geocodeCache[cacheKey] = result;
          return result;
        }
      }
    } catch (e) {
      debugPrint('Error in reverse geocoding: $e');
    }

    return {
      'city': 'Butuan City',
      'barangay': 'Downtown',
    };
  }

  /// Calculate distance in km between two lat/lng points
  static String calculateDistanceString(
    double startLat,
    double startLng,
    double endLat,
    double endLng,
  ) {
    final distanceInMeters = Geolocator.distanceBetween(
      startLat,
      startLng,
      endLat,
      endLng,
    );
    final distanceInKm = distanceInMeters / 1000.0;

    if (distanceInKm < 0.1) {
      return '${distanceInMeters.round()} m';
    }
    return '${distanceInKm.toStringAsFixed(1)} km';
  }
}
