import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geocoding/geocoding.dart';
import 'package:http/http.dart' as http;

final Map<String, String> geocodeAddressCache = {};

String geocodeCacheKey(double latitude, double longitude) =>
    '${latitude.toStringAsFixed(6)},${longitude.toStringAsFixed(6)}';

String? cachedGeocodedAddress(double latitude, double longitude) =>
    geocodeAddressCache[geocodeCacheKey(latitude, longitude)];

void cacheGeocodedAddress(double latitude, double longitude, String address) {
  final trimmed = address.trim();
  if (trimmed.isEmpty) return;
  geocodeAddressCache[geocodeCacheKey(latitude, longitude)] = trimmed;
}

String? addressFromPlacemark(Placemark p) {
  final parts = <String>[];
  for (final value in [
    p.street ?? p.name,
    p.subLocality,
    p.locality,
    p.administrativeArea,
  ]) {
    final text = value?.trim();
    if (text == null || text.isEmpty) continue;
    if (double.tryParse(text) != null) continue;
    if (!parts.contains(text)) parts.add(text);
  }
  if (parts.isEmpty) return null;
  return parts.join(', ');
}

bool looksLikeCoordinates(String? value) {
  if (value == null) return false;
  return RegExp(
    r'^\s*-?\d+(\.\d+)?\s*,\s*-?\d+(\.\d+)?\s*$',
  ).hasMatch(value.trim());
}

Future<String?> reverseGeocodeAddress(
  double latitude,
  double longitude, {
  bool allowNominatim = true,
}) async {
  final cached = cachedGeocodedAddress(latitude, longitude);
  if (cached != null) return cached;

  try {
    final placemarks = await placemarkFromCoordinates(latitude, longitude)
        .timeout(const Duration(seconds: 2), onTimeout: () => <Placemark>[]);
    if (placemarks.isNotEmpty) {
      final address = addressFromPlacemark(placemarks.first);
      if (address != null && address.isNotEmpty) {
        cacheGeocodedAddress(latitude, longitude, address);
        return address;
      }
    }
  } catch (_) {}

  // Nominatim is CORS-blocked in the browser and rate-limits quickly (429).
  if (!allowNominatim || kIsWeb) return null;

  try {
    final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
      'format': 'jsonv2',
      'lat': latitude.toString(),
      'lon': longitude.toString(),
    });
    final response = await http
        .get(
          uri,
          headers: const {'User-Agent': 'Orderx-Kamptec/1.0'},
        )
        .timeout(const Duration(seconds: 3));
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic>) {
        final display = (body['display_name'] as String?)?.trim();
        if (display != null && display.isNotEmpty) {
          cacheGeocodedAddress(latitude, longitude, display);
          return display;
        }
      }
    }
  } catch (_) {}

  return null;
}
