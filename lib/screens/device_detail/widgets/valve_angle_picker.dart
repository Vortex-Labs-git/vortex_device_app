import 'package:flutter/material.dart';

import '../../../theme/glass_theme.dart';

// =============================================================================
// VALVE ANGLE PICKER  (UI v2)
// =============================================================================
// The "set the valve to" block shared by the add-slot and add-rule sheets:
//
//   [ Close 0° ] [ Open 90° ]      the two common choices
//   Advanced ▾                     a slider for anything in between
//
// The fold opens by itself when the starting angle is in between, and shows
// the value in its header while folded. View + local fold state only; the
// sheet owns the angle.
// =============================================================================

class ValveAnglePicker extends StatefulWidget {
  final double angle;
  final ValueChanged<double> onChanged;
  final int min;
  final int max;

  /// Slider step in degrees.
  final int step;

  const ValveAnglePicker({
    super.key,
    required this.angle,
    required this.onChanged,
    this.min = 0,
    this.max = 90,
    this.step = 5,
  });

  @override
  State<ValveAnglePicker> createState() => _ValveAnglePickerState();
}

class _ValveAnglePickerState extends State<ValveAnglePicker> {
  late bool _open;

  @override
  void initState() {
    super.initState();
    final int a = widget.angle.round();
    _open = a != widget.min && a != widget.max;
  }

  @override
  Widget build(BuildContext context) {
    final int a = widget.angle.round();
    final bool between = a != widget.min && a != widget.max;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _Choice(
                label: 'Close',
                sub: '${widget.min}°',
                selected: a == widget.min,
                onTap: () => widget.onChanged(widget.min.toDouble()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Choice(
                label: 'Open',
                sub: '${widget.max}°',
                selected: a == widget.max,
                onTap: () => widget.onChanged(widget.max.toDouble()),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: GlassTokens.border),
            borderRadius: BorderRadius.circular(GlassTokens.radiusSm + 2),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              InkWell(
                onTap: () => setState(() => _open = !_open),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  child: Row(
                    children: [
                      const Icon(Icons.tune_rounded,
                          size: 18, color: GlassTokens.textSecondary),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Advanced',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: GlassTokens.textPrimary,
                          ),
                        ),
                      ),
                      if (between)
                        Text(
                          '$a°',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: GlassTokens.water,
                          ),
                        ),
                      const SizedBox(width: 4),
                      AnimatedRotation(
                        turns: _open ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(Icons.keyboard_arrow_down_rounded,
                            color: GlassTokens.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                alignment: Alignment.topCenter,
                child: !_open
                    ? const SizedBox(width: double.infinity)
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                        child: Column(
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  '$a°',
                                  style: const TextStyle(
                                    fontFamily: GlassTokens.displayFont,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                    color: GlassTokens.water,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  a == widget.min
                                      ? 'Closed'
                                      : a == widget.max
                                          ? 'Fully open'
                                          : 'Partly open',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: GlassTokens.textMuted,
                                  ),
                                ),
                              ],
                            ),
                            Slider(
                              value: widget.angle
                                  .clamp(widget.min, widget.max)
                                  .toDouble(),
                              min: widget.min.toDouble(),
                              max: widget.max.toDouble(),
                              divisions:
                                  (widget.max - widget.min) ~/ widget.step,
                              label: '$a°',
                              activeColor: GlassTokens.water,
                              onChanged: widget.onChanged,
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('${widget.min}° closed',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: GlassTokens.textMuted)),
                                Text('${widget.max}° open',
                                    style: const TextStyle(
                                        fontSize: 11,
                                        color: GlassTokens.textMuted)),
                              ],
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  final String label;
  final String sub;
  final bool selected;
  final VoidCallback onTap;

  const _Choice({
    required this.label,
    required this.sub,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color fg = selected ? GlassTokens.water : GlassTokens.textPrimary;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? GlassTokens.waterSoft : GlassTokens.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GlassTokens.radiusMd),
          side: BorderSide(
            color: selected ? GlassTokens.water : GlassTokens.border,
            width: 1.5,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(GlassTokens.radiusMd),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Column(
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
                Text(
                  sub,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? fg : GlassTokens.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
