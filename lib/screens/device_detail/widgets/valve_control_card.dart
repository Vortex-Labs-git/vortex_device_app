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
//   3. Advanced      the lever seen from above (what the valve reports, and
//                    a dashed outline of the angle being set), the 0–90°
//                    slider in 1° steps, and "Set valve to X°". Sends the
//                    same Set Angle command.
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
                        _LeverPicture(
                          actual: actualPosition.clamp(0, 90),
                          target: angle,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              '$angle°',
                              style: const TextStyle(
                                fontFamily: GlassTokens.displayFont,
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                                color: GlassTokens.water,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              angle == 0
                                  ? 'Closed'
                                  : angle == 90
                                      ? 'Fully open'
                                      : 'Partly open',
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: GlassTokens.textMuted,
                              ),
                            ),
                          ],
                        ),
                        // The old method: 0–90° in 1° steps.
                        Slider(
                          value: sliderAngle.clamp(0, 90),
                          min: 0,
                          max: 90,
                          divisions: 90,
                          label: '$angle°',
                          activeColor: GlassTokens.water,
                          onChanged: _busy ? null : onSliderChanged,
                          onChangeStart:
                              _busy ? null : (_) => onSliderEditStart(),
                          onChangeEnd: _busy ? null : (_) => onSliderEditEnd(),
                        ),
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('0° closed',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: GlassTokens.textMuted)),
                            Text('90° open',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: GlassTokens.textMuted)),
                          ],
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
// Lever picture: the valve seen from above. The lever on the stem lies across
// the pipe when closed (0°) and along it when open (90°), as on the real valve.
// Solid = what the valve reports (animates as reports arrive); dashed = the
// angle being set on the slider, shown only while it differs. Display only —
// the slider below does the setting.
// -----------------------------------------------------------------------------

class _LeverPicture extends StatelessWidget {
  final int actual;
  final int target;

  const _LeverPicture({required this.actual, required this.target});

  @override
  Widget build(BuildContext context) {
    final bool still = MediaQuery.of(context).disableAnimations;
    return Semantics(
      label: 'Valve lever at $actual degrees',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(GlassTokens.radiusMd),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: actual.toDouble()),
            duration: still ? Duration.zero : const Duration(milliseconds: 600),
            curve: Curves.easeInOutCubic,
            builder: (_, shown, _) => CustomPaint(
              painter: _LeverPainter(actual: shown, target: target),
            ),
          ),
        ),
      ),
    );
  }
}

class _LeverPainter extends CustomPainter {
  final double actual;
  final int target;

  _LeverPainter({required this.actual, required this.target});

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    final Offset c = Offset(w / 2, h * 0.62);
    final double u = h / 360; // design units: drawn at 640 x 360

    canvas.drawRect(Offset.zero & size, Paint()..color = GlassTokens.sunk);

    // Pipe, with water that deepens as the valve opens.
    final Rect pipe = Rect.fromLTRB(0, c.dy - 44 * u, w, c.dy + 44 * u);
    canvas.drawRect(pipe, Paint()..color = GlassTokens.metal);
    canvas.drawLine(pipe.topLeft, pipe.topRight,
        Paint()..color = GlassTokens.metalEdge..strokeWidth = 3 * u);
    canvas.drawLine(pipe.bottomLeft, pipe.bottomRight,
        Paint()..color = GlassTokens.metalEdge..strokeWidth = 3 * u);
    canvas.drawRect(
      Rect.fromLTRB(0, c.dy - 28 * u, w, c.dy + 28 * u),
      Paint()
        ..color = GlassTokens.water
            .withValues(alpha: 0.25 + 0.55 * (actual / 90).clamp(0, 1)),
    );

    // Valve body.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: c, width: 110 * u, height: 110 * u),
        Radius.circular(18 * u),
      ),
      Paint()..color = GlassTokens.metalSoft,
    );

    // Quarter-turn track and end marks.
    final Paint dashed = Paint()
      ..color = GlassTokens.textMuted
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * u;
    const int dashes = 14;
    for (int i = 0; i < dashes; i += 2) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: 128 * u),
        -math.pi / 2 + (math.pi / 2) * i / dashes,
        (math.pi / 2) / dashes,
        false,
        dashed,
      );
    }
    // Beside the two ends of the track, clear of the lever.
    _label(canvas, 'CLOSED', Offset(c.dx - 14 * u, c.dy - 150 * u), u,
        alignRight: true);
    _label(canvas, 'OPEN', Offset(c.dx + 120 * u, c.dy - 78 * u), u);

    // Target (dashed) when it differs, then the reported lever.
    if ((target - actual).abs() >= 1) _lever(canvas, c, target.toDouble(), u, ghost: true);
    _lever(canvas, c, actual, u);

    canvas.drawCircle(c, 13 * u, Paint()..color = GlassTokens.surface);
    canvas.drawCircle(
      c,
      13 * u,
      Paint()
        ..color = GlassTokens.forest
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5 * u,
    );
  }

  /// 0° points up (across the pipe), 90° points right (along it).
  void _lever(Canvas canvas, Offset c, double deg, double u,
      {bool ghost = false}) {
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate((deg - 90) * math.pi / 180);
    final RRect bar = RRect.fromRectAndRadius(
      Rect.fromLTWH(-14 * u, -14 * u, 132 * u, 28 * u),
      Radius.circular(14 * u),
    );
    if (ghost) {
      canvas.drawRRect(
        bar,
        Paint()
          ..color = GlassTokens.textMuted
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3 * u,
      );
    } else {
      canvas.drawRRect(bar, Paint()..color = GlassTokens.forest);
      canvas.drawCircle(
          Offset(104 * u, 0), 12 * u, Paint()..color = GlassTokens.gold);
    }
    canvas.restore();
  }

  void _label(Canvas canvas, String text, Offset at, double u,
      {bool alignRight = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: GlassTokens.bodyFont,
          fontSize: 18 * u,
          fontWeight: FontWeight.w800,
          color: GlassTokens.textSecondary,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, alignRight ? at - Offset(tp.width, 0) : at);
  }

  @override
  bool shouldRepaint(_LeverPainter old) =>
      old.actual != actual || old.target != target;
}
