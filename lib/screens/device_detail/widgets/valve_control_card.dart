import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../theme/glass_theme.dart';
import '../../../widgets/glass/glass.dart';

// =============================================================================
// VALVE CONTROL CARD  (UI v2)
// =============================================================================
// Manual control of the valve, laid out as:
//
//   1. "Valve now"   what the valve reports — OPEN, CLOSED, or the angle —
//                    or, while a command is out, where it is heading.
//   2. Action        only the next thing to do: "Close valve" when it is
//                    open, "Open valve" when it is closed, both (small) when it
//                    is part-way. Sends the same Open / Closed command.
//   3. Advanced      a quarter-turn handle to drag to any angle (1° steps),
//                    then "Set valve to X°". Sends the same Set Angle command.
//
// Same constructor as before. [valveControlEnabled] still means "state mode";
// it is now the Advanced fold: folded = state mode (true), open = angle mode
// (false), and toggling it calls [onValveControlEnabledChanged] exactly like
// the old switch did.
//
// All state lives in the parent screen. This widget renders and raises
// callbacks only.
// =============================================================================

class ValveControlCard extends StatelessWidget {
  final bool valveControlEnabled; // true = state mode, false = angle mode
  final ValueChanged<bool> onValveControlEnabledChanged;

  final bool isOpen;
  final int actualPosition;
  final bool isUpdating;
  final ValueChanged<bool> onOpenCloseToggled; // true=open, false=close

  final double sliderAngle;
  final bool isAngleUpdating;
  final ValueChanged<double> onSliderChanged;
  final VoidCallback onSliderEditStart;
  final VoidCallback onSliderEditEnd;
  final ValueChanged<int> onSetAnglePressed;

  final bool waitingForConfirmation;
  final int? pendingTargetAngle;
  final int confirmationCountdown;

  const ValveControlCard({
    super.key,
    required this.valveControlEnabled,
    required this.onValveControlEnabledChanged,
    required this.isOpen,
    required this.actualPosition,
    required this.isUpdating,
    required this.onOpenCloseToggled,
    required this.sliderAngle,
    required this.isAngleUpdating,
    required this.onSliderChanged,
    required this.onSliderEditStart,
    required this.onSliderEditEnd,
    required this.onSetAnglePressed,
    required this.waitingForConfirmation,
    required this.pendingTargetAngle,
    required this.confirmationCountdown,
  });

  /// Readings within this many degrees of an end count as fully closed /
  /// fully open, so a valve that settles at 88° still reads OPEN.
  static const int _endTolerance = 3;

  bool get _busy => isUpdating || isAngleUpdating || waitingForConfirmation;
  bool get _isClosed => actualPosition <= _endTolerance;
  bool get _isFullyOpen => actualPosition >= 90 - _endTolerance;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildStatus(),
          const SizedBox(height: 14),
          _buildAction(),
          const SizedBox(height: 12),
          _buildAdvanced(),
        ],
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // 1. Valve now
  // ───────────────────────────────────────────────────────────────────────

  Widget _buildStatus() {
    final int? target = waitingForConfirmation ? pendingTargetAngle : null;

    final String big;
    final String line;
    final Color color;
    if (target != null) {
      big = target <= _endTolerance
          ? 'CLOSING'
          : target >= 90 - _endTolerance
              ? 'OPENING'
              : 'TO $target°';
      line = 'Sent $target° · valve was at $actualPosition°';
      color = GlassTokens.textSecondary;
    } else if (_isClosed) {
      big = 'CLOSED';
      line = 'Closed · valve reports $actualPosition°';
      color = GlassTokens.textSecondary;
    } else if (_isFullyOpen) {
      big = 'OPEN';
      line = 'Fully open · valve reports $actualPosition°';
      color = GlassTokens.water;
    } else {
      big = '$actualPosition°';
      line = 'Partly open · valve reports $actualPosition°';
      color = GlassTokens.water;
    }

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'VALVE NOW',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.9,
                  color: GlassTokens.textMuted,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                big,
                style: TextStyle(
                  fontFamily: GlassTokens.displayFont,
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  height: 1.05,
                  color: color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                line,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: GlassTokens.textMuted,
                ),
              ),
            ],
          ),
        ),
        Icon(
          Icons.water_drop_outlined,
          size: 46,
          color: !_isClosed && target == null
              ? GlassTokens.water
              : GlassTokens.border,
        ),
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // 2. The next action
  // ───────────────────────────────────────────────────────────────────────

  Widget _buildAction() {
    if (_busy) {
      final bool closing = (pendingTargetAngle ?? (isOpen ? 90 : 0)) <
          _endTolerance + 1;
      return _ActionButton(
        label: waitingForConfirmation
            ? 'Waiting for the valve · ${confirmationCountdown}s'
            : 'Sending…',
        icon: null,
        color: closing ? GlassTokens.danger : GlassTokens.primary,
        busy: true,
        onPressed: null,
      );
    }

    if (_isClosed) {
      return _ActionButton(
        label: 'Open valve',
        icon: Icons.lock_open_rounded,
        color: GlassTokens.primary,
        onPressed: () => onOpenCloseToggled(true),
      );
    }
    if (_isFullyOpen) {
      return _ActionButton(
        label: 'Close valve',
        icon: Icons.lock_rounded,
        color: GlassTokens.danger,
        onPressed: () => onOpenCloseToggled(false),
      );
    }

    // Part-way: either direction makes sense.
    return Row(
      children: [
        Expanded(
          child: _SmallChoice(
            label: 'Close',
            sub: 'to 0°',
            color: GlassTokens.danger,
            onPressed: () => onOpenCloseToggled(false),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _SmallChoice(
            label: 'Open',
            sub: 'to 90°',
            color: GlassTokens.primary,
            onPressed: () => onOpenCloseToggled(true),
          ),
        ),
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────
  // 3. Advanced: turn handle + Set
  // ───────────────────────────────────────────────────────────────────────

  Widget _buildAdvanced() {
    final bool open = !valveControlEnabled;
    final int angle = sliderAngle.round();

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: GlassTokens.border),
        borderRadius: BorderRadius.circular(GlassTokens.radiusSm),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: GlassTokens.surface,
            child: InkWell(
              // Locked while waiting, like the old mode switch.
              onTap: waitingForConfirmation
                  ? null
                  : () => onValveControlEnabledChanged(open),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: Row(
                  children: [
                    const Icon(Icons.tune_rounded,
                        size: 18, color: GlassTokens.textSecondary),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Advanced · set an angle',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: GlassTokens.textPrimary,
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(Icons.keyboard_arrow_down_rounded,
                          color: GlassTokens.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: !open
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _TurnHandle(
                          angle: angle,
                          enabled: !_busy,
                          onChanged: (v) => onSliderChanged(v.toDouble()),
                          onStart: onSliderEditStart,
                          onEnd: onSliderEditEnd,
                        ),
                        const Text(
                          'Drag the handle like the real quarter-turn valve',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: GlassTokens.textMuted,
                          ),
                        ),
                        const SizedBox(height: 10),
                        GlassButton(
                          label: waitingForConfirmation
                              ? 'Waiting… ${confirmationCountdown}s'
                              : isAngleUpdating
                                  ? 'Sending…'
                                  : 'Set valve to $angle°',
                          icon: Icons.send_rounded,
                          isLoading: isAngleUpdating,
                          onPressed: _busy
                              ? null
                              : () => onSetAnglePressed(angle),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Buttons
// -----------------------------------------------------------------------------

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;
  final bool busy;
  final VoidCallback? onPressed;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    this.busy = false,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          disabledBackgroundColor: color.withValues(alpha: 0.65),
          disabledForegroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(GlassTokens.radiusMd),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            else if (icon != null)
              Icon(icon, size: 20),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallChoice extends StatelessWidget {
  final String label;
  final String sub;
  final Color color;
  final VoidCallback onPressed;

  const _SmallChoice({
    required this.label,
    required this.sub,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: GlassTokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GlassTokens.radiusMd),
        side: const BorderSide(color: GlassTokens.border, width: 1.5),
      ),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(GlassTokens.radiusMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              Text(
                sub,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: GlassTokens.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Turn handle: a quarter-turn dial. 0° points up (closed), 90° points right
// (open). Drag anywhere on it; the angle follows the finger in 1° steps.
// -----------------------------------------------------------------------------

class _TurnHandle extends StatelessWidget {
  final int angle;
  final bool enabled;
  final ValueChanged<int> onChanged;
  final VoidCallback onStart;
  final VoidCallback onEnd;

  const _TurnHandle({
    required this.angle,
    required this.enabled,
    required this.onChanged,
    required this.onStart,
    required this.onEnd,
  });

  static const double _size = 210;

  void _update(Offset local) {
    final Offset c = const Offset(_size / 2, _size / 2);
    final double dx = local.dx - c.dx;
    final double dy = c.dy - local.dy;
    // Clockwise from straight up.
    final double deg = math.atan2(dx, dy) * 180 / math.pi;
    final int v = deg.round().clamp(0, 90);
    if (v != angle) onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      slider: true,
      label: 'Valve angle',
      value: '$angle degrees',
      increasedValue: '${(angle + 5).clamp(0, 90)} degrees',
      decreasedValue: '${(angle - 5).clamp(0, 90)} degrees',
      onIncrease: enabled ? () => onChanged((angle + 5).clamp(0, 90)) : null,
      onDecrease: enabled ? () => onChanged((angle - 5).clamp(0, 90)) : null,
      child: Center(
        child: Opacity(
          opacity: enabled ? 1 : 0.6,
          child: GestureDetector(
            onPanStart: enabled
                ? (d) {
                    onStart();
                    _update(d.localPosition);
                  }
                : null,
            onPanUpdate: enabled ? (d) => _update(d.localPosition) : null,
            onPanEnd: enabled ? (_) => onEnd() : null,
            onTapUp: enabled
                ? (d) {
                    onStart();
                    _update(d.localPosition);
                    onEnd();
                  }
                : null,
            child: SizedBox(
              width: _size,
              height: _size,
              child: CustomPaint(painter: _HandlePainter(angle)),
            ),
          ),
        ),
      ),
    );
  }
}

class _HandlePainter extends CustomPainter {
  final int angle;

  _HandlePainter(this.angle);

  @override
  void paint(Canvas canvas, Size size) {
    final Offset c = size.center(Offset.zero);
    final double r = size.width / 2 - 14;
    final Rect dial = Rect.fromCircle(center: c, radius: r);
    const double up = -math.pi / 2;

    // Dial face, the 0–90° quarter, and the current opening.
    canvas.drawCircle(c, r, Paint()..color = GlassTokens.sunk);
    canvas.drawArc(dial, up, math.pi / 2, true,
        Paint()..color = GlassTokens.waterSoft);
    if (angle > 0) {
      canvas.drawArc(dial, up, angle * math.pi / 180, true,
          Paint()..color = GlassTokens.water.withValues(alpha: 0.35));
    }

    // End labels.
    void label(String text, Offset at) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(
            fontFamily: GlassTokens.bodyFont,
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            color: GlassTokens.textMuted,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
    }

    label('CLOSED 0°', Offset(c.dx, 6));
    label('OPEN 90°', Offset(size.width - 22, c.dy - 12));

    // Hub ring.
    canvas.drawCircle(c, r * 0.46, Paint()..color = GlassTokens.surface);
    canvas.drawCircle(
      c,
      r * 0.46,
      Paint()
        ..color = GlassTokens.border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Handle, rotated by the angle.
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle * math.pi / 180);
    final RRect bar = RRect.fromRectAndRadius(
      Rect.fromLTWH(-8, -r * 0.78, 16, r * 0.78 + 4),
      const Radius.circular(8),
    );
    canvas.drawRRect(bar, Paint()..color = GlassTokens.forest);
    canvas.drawCircle(
        Offset(0, -r * 0.72), 10, Paint()..color = GlassTokens.gold);
    canvas.restore();

    canvas.drawCircle(c, 9, Paint()..color = GlassTokens.surface);
    canvas.drawCircle(
      c,
      9,
      Paint()
        ..color = GlassTokens.forest
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    // Angle readout under the hub.
    final tp = TextPainter(
      text: TextSpan(
        text: '$angle°',
        style: const TextStyle(
          fontFamily: GlassTokens.displayFont,
          fontSize: 26,
          fontWeight: FontWeight.w800,
          color: GlassTokens.textPrimary,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(c.dx - tp.width / 2, c.dy + r * 0.5));
  }

  @override
  bool shouldRepaint(_HandlePainter old) => old.angle != angle;
}
