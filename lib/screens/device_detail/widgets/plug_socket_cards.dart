import 'package:flutter/material.dart';

import '../../../models/smart_plug.dart';
import '../../../theme/glass_theme.dart';

// =============================================================================
// PLUG SOCKET CARDS  (UI v2)
// =============================================================================
// The plug's sockets (bases) under the header. Replaces PlugBaseSelector and
// PlugBaseHeaderCard:
//
//   dual plug    two cards side by side — name, ON/OFF, watts. Tap one to
//                control it; the selected card gets a green ring.
//   single plug  one full-width card. There is no Socket B anywhere.
//
// The selected card carries the rename button. Offline, the watts turn grey
// and read "last value". ON/OFF is always what the PLUG reports (state).
// View only: selection and rename are callbacks to the screen.
// =============================================================================

class PlugSocketCards extends StatelessWidget {
  /// Valid sockets only (SmartPlug.bases): one or two.
  final List<PlugBase> bases;
  final PlugBaseId selected;
  final bool isOffline;
  final ValueChanged<PlugBaseId> onSelected;

  /// Renames the selected socket.
  final VoidCallback onEditName;

  const PlugSocketCards({
    super.key,
    required this.bases,
    required this.selected,
    required this.isOffline,
    required this.onSelected,
    required this.onEditName,
  });

  @override
  Widget build(BuildContext context) {
    if (bases.length < 2) {
      return bases.isEmpty
          ? const SizedBox.shrink()
          : _SingleCard(
              base: bases.first,
              isOffline: isOffline,
              onEditName: onEditName,
            );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < bases.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            Expanded(
              child: _SocketCard(
                base: bases[i],
                selected: bases[i].id == selected,
                isOffline: isOffline,
                onTap: () => onSelected(bases[i].id),
                onEditName: onEditName,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Card frame shared by both layouts: white, green ring when selected.
class _Frame extends StatelessWidget {
  final bool selected;
  final VoidCallback? onTap;
  final Widget child;

  const _Frame({required this.selected, this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(GlassTokens.radiusMd);
    return Semantics(
      selected: selected,
      button: onTap != null,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: selected
              ? const [
                  BoxShadow(color: GlassTokens.leafSoft, spreadRadius: 3),
                ]
              : null,
        ),
        child: Material(
          color: GlassTokens.surface,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(
              color: selected ? GlassTokens.primary : GlassTokens.border,
              width: 1.5,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(onTap: onTap, child: child),
        ),
      ),
    );
  }
}

class _SocketCard extends StatelessWidget {
  final PlugBase base;
  final bool selected;
  final bool isOffline;
  final VoidCallback onTap;
  final VoidCallback onEditName;

  const _SocketCard({
    required this.base,
    required this.selected,
    required this.isOffline,
    required this.onTap,
    required this.onEditName,
  });

  @override
  Widget build(BuildContext context) {
    final bool lit = base.state && !isOffline;
    return _Frame(
      selected: selected,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(11, 10, 6, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.power_settings_new_rounded,
                  size: 18,
                  color: lit ? GlassTokens.primary : GlassTokens.textMuted,
                ),
                const SizedBox(width: 6),
                Expanded(child: _Name(base.name, fontSize: 13.5)),
                const SizedBox(width: 4),
                _StatePill(on: base.state),
                const SizedBox(width: 4),
              ],
            ),
            const SizedBox(height: 6),
            _Watts(base: base, isOffline: isOffline, fontSize: 21),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Socket ${base.id.letter}'
                    '${isOffline ? ' · last value' : ''}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: GlassTokens.textMuted,
                    ),
                  ),
                ),
                if (selected)
                  _EditButton(onPressed: onEditName)
                else
                  const SizedBox(height: 32),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SingleCard extends StatelessWidget {
  final PlugBase base;
  final bool isOffline;
  final VoidCallback onEditName;

  const _SingleCard({
    required this.base,
    required this.isOffline,
    required this.onEditName,
  });

  @override
  Widget build(BuildContext context) {
    final bool lit = base.state && !isOffline;
    return _Frame(
      selected: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(
          children: [
            Icon(
              Icons.power_settings_new_rounded,
              size: 26,
              color: lit ? GlassTokens.primary : GlassTokens.textMuted,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(child: _Name(base.name, fontSize: 14.5)),
                      const SizedBox(width: 6),
                      _StatePill(on: base.state),
                    ],
                  ),
                  Text(
                    'Socket ${base.id.letter}'
                    '${isOffline ? ' · last value' : ''}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: GlassTokens.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _Watts(base: base, isOffline: isOffline, fontSize: 21),
            _EditButton(onPressed: onEditName),
          ],
        ),
      ),
    );
  }
}

class _Name extends StatelessWidget {
  final String text;
  final double fontSize;

  const _Name(this.text, {required this.fontSize});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
        color: GlassTokens.textPrimary,
      ),
    );
  }
}

class _Watts extends StatelessWidget {
  final PlugBase base;
  final bool isOffline;
  final double fontSize;

  const _Watts({
    required this.base,
    required this.isOffline,
    required this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      base.wattageLabel,
      maxLines: 1,
      style: TextStyle(
        fontFamily: GlassTokens.displayFont,
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
        color: base.state && !isOffline
            ? GlassTokens.textPrimary
            : GlassTokens.textMuted,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

class _StatePill extends StatelessWidget {
  final bool on;

  const _StatePill({required this.on});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: on ? GlassTokens.leafSoft : GlassTokens.sunk,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        on ? 'ON' : 'OFF',
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          color: on ? GlassTokens.success : GlassTokens.textMuted,
        ),
      ),
    );
  }
}

class _EditButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _EditButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Rename socket',
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      padding: EdgeInsets.zero,
      icon: const Icon(Icons.edit_outlined,
          size: 18, color: GlassTokens.textMuted),
    );
  }
}
