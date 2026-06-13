import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

typedef IpLatLng = ({double lat, double lng});

/// Approximate device coordinates from public-IP geolocation (ipapi.co), cached
/// for a day in SharedPreferences so we don't hit the API on every screen.
/// Returns null only when never resolved (e.g. offline on first run) — callers
/// then fall back to a nominal day/night clock. Used to compute real sunrise/
/// sunset for the screensaver; works pre-login (no auth needed).
final ipLocationProvider = FutureProvider<IpLatLng?>((ref) async {
  const latKey = 'ipgeo_lat', lngKey = 'ipgeo_lng', tsKey = 'ipgeo_ts';
  const maxAge = Duration(days: 1);

  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (_) {}

  IpLatLng? cached;
  if (prefs != null) {
    final lat = prefs.getDouble(latKey);
    final lng = prefs.getDouble(lngKey);
    final ts = prefs.getInt(tsKey) ?? 0;
    if (lat != null && lng != null) {
      cached = (lat: lat, lng: lng);
      final ageMs = DateTime.now().millisecondsSinceEpoch - ts;
      if (ageMs >= 0 && ageMs < maxAge.inMilliseconds) return cached; // still fresh
    }
  }

  try {
    final res = await http
        .get(Uri.parse('https://ipapi.co/json/'))
        .timeout(const Duration(seconds: 5));
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final lat = (data['latitude'] as num?)?.toDouble();
      final lng = (data['longitude'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        if (prefs != null) {
          await prefs.setDouble(latKey, lat);
          await prefs.setDouble(lngKey, lng);
          await prefs.setInt(tsKey, DateTime.now().millisecondsSinceEpoch);
        }
        return (lat: lat, lng: lng);
      }
    }
  } catch (_) {}

  return cached; // stale cache if the refresh failed, else null
});
