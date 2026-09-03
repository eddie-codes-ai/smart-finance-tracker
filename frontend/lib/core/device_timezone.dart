// lib/core/device_timezone.dart
//
// Reads the device's IANA time zone name, e.g. "Africa/Nairobi".
//
// Dart's own DateTime.timeZoneName is not usable for this: it returns a
// platform-dependent abbreviation like "EAT" or "Eastern Standard Time", which
// the server cannot look up. flutter_timezone goes to the native layer for the
// real identifier.
//
// This is only ever a *suggestion*. The zone the app actually reports by is the
// user's saved home zone on the server, so that travelling does not silently
// re-bucket their spending history.

import 'package:flutter/foundation.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

class DeviceTimezone {
  /// Fallback matching the server's own default, used when the platform
  /// channel is unavailable (an emulator quirk, a permissions oddity, or a
  /// platform the plugin does not cover).
  static const String fallback = 'Africa/Nairobi';

  static String? _cached;

  /// The device's IANA zone name, or [fallback] if it can't be determined.
  ///
  /// Never throws: failing to read a time zone must not be able to block
  /// registration or leave the profile screen stuck.
  static Future<String> current() async {
    final cached = _cached;
    if (cached != null) return cached;
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      final identifier = info.identifier.trim();
      _cached = identifier.isEmpty ? fallback : identifier;
    } catch (e) {
      debugPrint('Could not read the device time zone: $e');
      _cached = fallback;
    }
    return _cached!;
  }

  /// Forget the cached value, so a zone change is picked up without a restart.
  static void invalidate() => _cached = null;
}
