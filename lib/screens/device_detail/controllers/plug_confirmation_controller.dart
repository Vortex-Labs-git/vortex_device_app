import 'dart:async';

import '../../../models/smart_plug.dart';

// =============================================================================
// PLUG CONFIRMATION CONTROLLER
// =============================================================================
// The plug's version of ValveConfirmationController. After an ON/OFF command
// we wait for the base's reported `state` to match the target. Each base has
// its own wait, so switching Base A doesn't lock Base B.
//
// The screen feeds it every device_basic_detail push (via [reportPlug]) and
// rebuilds on [onChanged].
// =============================================================================

/// How long to wait for a base to report its new state through the cloud.
const int kPlugConfirmationTimeoutSeconds = 20;

class PlugConfirmationController {
  /// Called whenever the visible state changes (countdown tick, start, finish).
  final void Function() onChanged;

  /// Called when [base] reported the target state.
  final void Function(PlugBaseId base, bool state) onSuccess;

  /// Called when the countdown for [base] ran out.
  final void Function(PlugBaseId base, bool expected) onTimeout;

  PlugConfirmationController({
    required this.onChanged,
    required this.onSuccess,
    required this.onTimeout,
  });

  final Map<PlugBaseId, _Wait> _waits = {};

  bool isWaiting(PlugBaseId base) => _waits.containsKey(base);
  bool? targetState(PlugBaseId base) => _waits[base]?.target;
  int countdown(PlugBaseId base) => _waits[base]?.countdown ?? 0;

  /// Begins waiting for [base] to report [target].
  void start(
    PlugBaseId base,
    bool target, {
    int timeoutSeconds = kPlugConfirmationTimeoutSeconds,
  }) {
    _waits[base]?.timer.cancel();

    final wait = _Wait(target: target, countdown: timeoutSeconds);
    wait.timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      wait.countdown--;
      if (wait.countdown <= 0) {
        timer.cancel();
        _waits.remove(base);
        onChanged();
        onTimeout(base, target);
      } else {
        onChanged();
      }
    });

    _waits[base] = wait;
    onChanged();
  }

  /// Feed every parsed device_basic_detail here. Confirms any base whose
  /// reported state now matches its pending target.
  void reportPlug(SmartPlug plug) {
    for (final id in _waits.keys.toList()) {
      final wait = _waits[id]!;
      if (plug.base(id).state != wait.target) continue;
      wait.timer.cancel();
      _waits.remove(id);
      onChanged();
      onSuccess(id, wait.target);
    }
  }

  void dispose() {
    for (final w in _waits.values) {
      w.timer.cancel();
    }
    _waits.clear();
  }
}

class _Wait {
  final bool target;
  int countdown;
  late Timer timer;

  _Wait({required this.target, required this.countdown});
}