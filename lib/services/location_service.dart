import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Data class holding verified user location details
class LocationData {
  final double latitude;
  final double longitude;
  final String city;
  final String barangay;
  final DateTime updatedAt;

  LocationData({
    required this.latitude,
    required this.longitude,
    required this.city,
    required this.barangay,
    required this.updatedAt,
  });
}

/// Optimized Location Service with Reactive ValueNotifier, GPS Stream & Dual Geocoding
class LocationService {
  static Position? _cachedPosition;
  static DateTime? _lastGPSFetchTime;
  static final Map<String, Map<String, String>> _geocodeCache = {};

  /// Reactive global location notifier for seamless instant UI updates across screens
  static final ValueNotifier<LocationData?> currentLocationNotifier = ValueNotifier(null);
  static StreamSubscription<Position>? _positionStreamSub;

  /// Call once during app startup (e.g. in splash screen or main)
  static Future<void> initializeOnStartup() async {
    // 1. Instant SharedPreferences cache restore
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedLat = prefs.getDouble('last_loc_lat');
      final savedLng = prefs.getDouble('last_loc_lng');
      final savedCity = prefs.getString('last_loc_city');
      final savedBarangay = prefs.getString('last_loc_barangay');

      if (savedLat != null && savedLng != null && savedCity != null) {
        currentLocationNotifier.value = LocationData(
          latitude: savedLat,
          longitude: savedLng,
          city: savedCity,
          barangay: savedBarangay ?? 'Nearby Area',
          updatedAt: DateTime.now(),
        );
      }
    } catch (e) {
      debugPrint('Error loading cached location from prefs: $e');
    }

    // 2. Fetch fresh high-precision GPS position in background
    refreshLocation(forceRefresh: true);

    // 3. Start movement-driven GPS stream (updates only when user moves > 100 meters)
    _startPositionStream();
  }

  /// Manually or automatically refresh position and update global notifier
  static Future<LocationData?> refreshLocation({bool forceRefresh = false}) async {
    final pos = await getCurrentPosition(forceRefresh: forceRefresh);
    if (pos != null) {
      final locData = await getCityAndBarangay(pos.latitude, pos.longitude);
      final data = LocationData(
        latitude: pos.latitude,
        longitude: pos.longitude,
        city: locData['city'] ?? 'Current City',
        barangay: locData['barangay'] ?? 'Nearby Area',
        updatedAt: DateTime.now(),
      );
      currentLocationNotifier.value = data;
      _saveToPrefs(data);
      return data;
    }
    return currentLocationNotifier.value;
  }

  static void _startPositionStream() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled()
          .timeout(const Duration(seconds: 3), onTimeout: () => false);
      if (!serviceEnabled) return;
      LocationPermission permission = await Geolocator.checkPermission()
          .timeout(const Duration(seconds: 3), onTimeout: () => LocationPermission.denied);
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return;

      _positionStreamSub?.cancel();
      _positionStreamSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          distanceFilter: 100, // Only triggers when device physically moves 100+ meters
        ),
      ).listen((Position position) async {
        final locData = await getCityAndBarangay(position.latitude, position.longitude);
        final data = LocationData(
          latitude: position.latitude,
          longitude: position.longitude,
          city: locData['city'] ?? 'Current City',
          barangay: locData['barangay'] ?? 'Nearby Area',
          updatedAt: DateTime.now(),
        );
        currentLocationNotifier.value = data;
        _saveToPrefs(data);
      });
    } catch (e) {
      debugPrint('Error starting position stream: $e');
    }
  }

  static Future<void> _saveToPrefs(LocationData data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('last_loc_lat', data.latitude);
      await prefs.setDouble('last_loc_lng', data.longitude);
      await prefs.setString('last_loc_city', data.city);
      await prefs.setString('last_loc_barangay', data.barangay);
    } catch (e) {
      debugPrint('Error saving location to prefs: $e');
    }
  }

  /// Check permission and get user's current GPS position with high accuracy
  static Future<Position?> getCurrentPosition({bool forceRefresh = false}) async {
    // Return cached position if fetched within the last 30 seconds and forceRefresh is false
    if (!forceRefresh && _cachedPosition != null && _lastGPSFetchTime != null) {
      if (DateTime.now().difference(_lastGPSFetchTime!) < const Duration(seconds: 30)) {
        return _cachedPosition;
      }
    }

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled()
          .timeout(const Duration(seconds: 3), onTimeout: () => false);
      if (!serviceEnabled) {
        debugPrint('Location services are disabled.');
        return _cachedPosition;
      }

      LocationPermission permission = await Geolocator.checkPermission()
          .timeout(const Duration(seconds: 3), onTimeout: () => LocationPermission.denied);
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission()
            .timeout(const Duration(seconds: 10), onTimeout: () => LocationPermission.denied);
        if (permission == LocationPermission.denied) {
          debugPrint('Location permissions are denied');
          return _cachedPosition;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('Location permissions are permanently denied.');
        return _cachedPosition;
      }

      // High precision fresh position when forceRefresh is true
      if (forceRefresh) {
        Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 8),
        );
        _cachedPosition = position;
        _lastGPSFetchTime = DateTime.now();
        return position;
      }

      // Fast last known position fallback
      Position? position = await Geolocator.getLastKnownPosition();
      if (position != null) {
        _cachedPosition = position;
        _lastGPSFetchTime = DateTime.now();
        return position;
      }

      // Fetch fresh position with high accuracy
      position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 6),
      );

      _cachedPosition = position;
      _lastGPSFetchTime = DateTime.now();
      return position;
    } catch (e) {
      debugPrint('Error getting current position: $e');
      return _cachedPosition;
    }
  }

  /// Reverse geocode coordinates to City & Barangay with dual API fallbacks
  static Future<Map<String, String>> getCityAndBarangay(double lat, double lng) async {
    final cacheKey = '${lat.toStringAsFixed(3)}_${lng.toStringAsFixed(3)}';
    if (_geocodeCache.containsKey(cacheKey)) {
      return _geocodeCache[cacheKey]!;
    }

    // 1. Primary: OpenStreetMap Nominatim
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=$lat&lon=$lng&zoom=18&addressdetails=1',
      );
      final response = await http.get(
        url,
        headers: {
          'User-Agent': 'iHanapApp/2.0 (contact@ihanap.ph)',
          'Accept-Language': 'en-US,en;q=0.9',
        },
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final address = data['address'] as Map<String, dynamic>?;

        if (address != null) {
          final city = address['city'] ??
              address['municipality'] ??
              address['town'] ??
              address['city_district'] ??
              address['county'] ??
              address['state_district'] ??
              address['state'] ??
              'Local Area';

          final barangay = address['quarter'] ??
              address['suburb'] ??
              address['village'] ??
              address['neighbourhood'] ??
              address['hamlet'] ??
              address['residential'] ??
              address['road'] ??
              'Nearby Area';

          final result = {
            'city': city.toString(),
            'barangay': barangay.toString(),
          };

          _geocodeCache[cacheKey] = result;
          return result;
        }
      }
    } catch (e) {
      debugPrint('Error in primary reverse geocoding: $e');
    }

    // 2. Secondary Fallback: BigDataCloud Reverse Geocode API
    try {
      final url = Uri.parse(
        'https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=$lat&longitude=$lng&localityLanguage=en',
      );
      final response = await http.get(url).timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final city = data['city'] ?? data['locality'] ?? data['principalSubdivision'] ?? 'Current Area';
        final barangay = data['locality'] ?? 'Nearby Area';
        final result = {
          'city': city.toString(),
          'barangay': barangay.toString(),
        };
        _geocodeCache[cacheKey] = result;
        return result;
      }
    } catch (e) {
      debugPrint('Error in secondary reverse geocoding: $e');
    }

    // Dynamic coordinates fallback if network APIs fail
    return {
      'city': 'Your Area',
      'barangay': 'Local Area',
    };
  }

  /// Calculate distance in km between two lat/lng points (Haversine formula)
  static double calculateDistanceKm(
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
    return distanceInMeters / 1000.0;
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
