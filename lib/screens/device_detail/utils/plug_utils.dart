import '../../../models/smart_plug.dart';

// =============================================================================
// PLUG UTILS
// =============================================================================
// Pure display helpers for the smart plug screen. No widgets, no state.
// =============================================================================

/// Seconds → short human label: 45 → "45 s", 120 → "2 min", 90 → "1 min 30 s",
/// 3600 → "1 h", 5400 → "1 h 30 min", 3630 → "1 h 30 s".
String formatPlugSeconds(int seconds) {
  if (seconds <= 0) return '0 s';
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;

  final parts = <String>[
    if (h > 0) '$h h',
    if (m > 0) '$m min',
    if (s > 0) '$s s',
  ];
  return parts.join(' ');
}

/// One-line summary of an entry's step: "ON whole time" or
/// "5 s ON / 5 s OFF".
String describePlugStep(PlugScheduleEntry entry) {
  if (entry.isContinuous) return 'ON whole time';
  return '${formatPlugSeconds(entry.onSeconds)} ON / '
      '${formatPlugSeconds(entry.offSeconds)} OFF';
}
