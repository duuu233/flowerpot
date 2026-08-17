import 'package:flutter/foundation.dart';

/// Availability of the in-app Tuya SDK console.
///
/// Debug and profile builds always expose it. A release build has to opt in
/// with `--dart-define=TUYA_DEBUG_TOOLS=true`, which keeps a raw SDK console
/// out of store builds while it stays reachable in a release-signed test APK —
/// on machines without `android/key.properties` that is the only build whose
/// certificate matches the SHA-256 registered on the Tuya platform.
abstract final class DebugToolsConfig {
  static const forced = bool.fromEnvironment('TUYA_DEBUG_TOOLS');

  static bool get enabled => forced || !kReleaseMode;
}
