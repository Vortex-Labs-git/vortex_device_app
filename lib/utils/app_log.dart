import 'package:flutter/foundation.dart';

// =============================================================================
// APP LOG
// =============================================================================
// Drop-in replacement for the bare print() calls that used to litter the
// services and controllers.
//
// WHY THIS EXISTS:
//   print() writes to the system log in EVERY build, including release. On a
//   shipped app those lines are readable by anything with adb access, and this
//   codebase logged JWTs, device IDs and network state. kDebugMode is a
//   compile-time constant, so in release the call and its string interpolation
//   are tree-shaken away entirely — there is no runtime cost and nothing to
//   leak.
//
// USE debugPrint, NOT print:
//   debugPrint throttles output, so the 2-second valve polling loops can no
//   longer overflow the platform log buffer and drop lines you care about.
//
// The controllers additionally mirror their lines to a logStream for the
// debug terminal — that is unaffected by this and stays on in release.
// =============================================================================

/// Logs [message] in debug and profile builds only. Compiled out of release.
void logD(String message) {
  if (kDebugMode) {
    debugPrint(message);
  }
}
