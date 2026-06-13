import 'dart:math' as math;

import 'package:flutter/material.dart' show Brightness;

/// Whether the sun is above the horizon at [when] for the given coordinates,
/// using a low-precision solar-position formula (the Astronomical Almanac's
/// "approximate solar coordinates"). Accurate to a few minutes — ample for a
/// day/night decision — and handles polar day/night naturally (the altitude
/// simply stays above/below the horizon all day).
bool isSunUp(double lat, double lng, DateTime when) {
  final utc = when.toUtc();
  // Days (incl. fraction) since the J2000.0 epoch, 2000-01-01 12:00 UTC.
  final n = utc.difference(DateTime.utc(2000, 1, 1, 12)).inMilliseconds / 86400000.0;

  double rad(double deg) => deg * math.pi / 180.0;

  final meanLong = (280.460 + 0.9856474 * n) % 360;       // mean longitude (°)
  final meanAnom = rad((357.528 + 0.9856003 * n) % 360);  // mean anomaly
  // Ecliptic longitude.
  final lambda = rad(meanLong + 1.915 * math.sin(meanAnom) + 0.020 * math.sin(2 * meanAnom));
  final obliquity = rad(23.439 - 0.0000004 * n);          // obliquity of ecliptic

  final declination = math.asin(math.sin(obliquity) * math.sin(lambda));
  final rightAsc = math.atan2(math.cos(obliquity) * math.sin(lambda), math.cos(lambda));

  // Greenwich + local apparent sidereal time → hour angle of the sun.
  final gmst = (280.46061837 + 360.98564736629 * n) % 360;
  final lst = rad((gmst + lng) % 360);
  var hourAngle = lst - rightAsc;
  hourAngle = math.atan2(math.sin(hourAngle), math.cos(hourAngle)); // normalise to [-π, π]

  final latR = rad(lat);
  final sinAltitude = math.sin(latR) * math.sin(declination) +
      math.cos(latR) * math.cos(declination) * math.cos(hourAngle);
  final altitudeDeg = math.asin(sinAltitude.clamp(-1.0, 1.0)) * 180.0 / math.pi;

  // -0.833° is the standard horizon dip (atmospheric refraction + solar radius).
  return altitudeDeg > -0.833;
}

/// Day/night brightness for the screensaver: real solar position when [lat]/
/// [lng] are known (from IP geolocation), otherwise a nominal 06:00–18:00 clock
/// fallback. Light during the day, dark at night.
Brightness sunBrightness({double? lat, double? lng, DateTime? now}) {
  final t = now ?? DateTime.now();
  if (lat != null && lng != null) {
    return isSunUp(lat, lng, t) ? Brightness.light : Brightness.dark;
  }
  final h = t.hour; // fallback: no location resolved yet
  return (h >= 6 && h < 18) ? Brightness.light : Brightness.dark;
}
