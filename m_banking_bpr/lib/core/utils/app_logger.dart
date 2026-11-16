import 'package:flutter/foundation.dart';

/// Debug-only logging. `debugPrint` is NOT stripped from release builds, so
/// diagnostic output (push payloads, backend responses, errors) goes through
/// this helper and is suppressed outside debug mode (audit DMB-011 / DMB-034).
void logDebug(String message) {
  if (kDebugMode) debugPrint(message);
}
