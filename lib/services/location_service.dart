import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class LocationService {
  /// Check permission and get user's current GPS position
  static Future<Position?> getCurrentPosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    // Test if location services are enabled.
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('Location services are disabled.');
      return null;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint('Location permissions are denied');
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      debugPrint('Location permissions are permanently denied.');
      return null;
    }

    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
    } catch (e) {
      debugPrint('Error getting current position: $e');
      return null;
    }
  }

  /// Reverse geocode coordinates to City & Barangay/District name
  static Future<Map<String, String>> getCityAndBarangay(double lat, double lng) async {
    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=$lat&lon=$lng',
      );
      final response = await http.get(
        url,
        headers: {'User-Agent': 'iHanapApp/1.0 (contact@ihanap.ph)'},
      );

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

          return {
            'city': city.toString(),
            'barangay': barangay.toString(),
          };
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
