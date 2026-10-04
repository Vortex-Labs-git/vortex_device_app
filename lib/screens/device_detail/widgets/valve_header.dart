import 'package:flutter/material.dart';

import '../../../theme/glass_theme.dart';
import '../../../widgets/glass/glass.dart';

// =============================================================================
// VALVE HEADER  (UI v2)
// =============================================================================
// The forest band at the top of the valve screen. It replaces both the app
// bar and the old DeviceInfoCard on this screen: back button, product line,
// connection icon, product photo, name (tap to rename), ID / version and the
// status tag.
//
// Direct mode switches the product line and tag to gold ("Direct link · no
// internet needed" / "Direct connected"), the same signal the gold dot gives
// on Home.
//
// The sensor unit screen uses the same band with its own [productLine],
// photo and fallback icon.
//
// View only: every value and callback comes from DeviceDetailScreen.
// =============================================================================

class ValveHeader extends StatelessWidget {
  final String deviceName;
  final String deviceId;
  final String productType;
  final bool isOnline;
  final bool isDirectMode;

  /// Live link state (server WebSocket, or the ESP32 socket in direct mode).
  final bool linkConnected;

  final VoidCallback onEditName;

  /// Top-row label outside direct mode.
  final String productLine;

  /// Product photo, and the icon shown if it fails to load.
  final String imageAsset;
  final IconData fallbackIcon;

  const ValveHeader({
    super.key,
    required this.deviceName,
    required this.deviceId,
    required this.productType,
    required this.isOnline,
    required this.isDirectMode,
    required this.linkConnected,
    required this.onEditName,
    this.productLine = 'Motorized valve',
    this.imageAsset = 'assets/images/VA_3.jpeg',
    this.fallbackIcon = Icons.water_drop_outlined,
  });

  @override
  Widget build(BuildContext context) {
    final Color lineColor =
        isDirectMode ? GlassTokens.gold : Colors.white.withValues(alpha: 0.75);

    return ForestHeader(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 18),
      radius: 24,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top row: back · product line · link icon ──
          Row(
            children: [
              _HeaderButton(
                icon: Icons.chevron_left_rounded,
                tooltip: 'Back',
                onTap: () => Navigator.of(context).maybePop(),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isDirectMode
                      ? 'Direct link · no internet needed'
                      : productLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: lineColor,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _HeaderButton(
                icon: !linkConnected
                    ? Icons.wifi_off_rounded
                    : isDirectMode
                        ? Icons.settings_input_antenna_rounded
                        : Icons.wifi_rounded,
                iconColor: !linkConnected
                    ? GlassTokens.onForestDanger
                    : isDirectMode
                        ? GlassTokens.gold
                        : Colors.white,
                tooltip: linkConnected ? 'Connected' : 'Not connected',
              ),
            ],
          ),

          const SizedBox(height: 14),

          // ── Identity: photo · name / ID / status ──
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(GlassTokens.radiusMd),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.asset(
                  imageAsset,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Icon(
                    fallbackIcon,
                    color: GlassTokens.water,
                    size: 30,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: onEditName,
                      borderRadius: BorderRadius.circular(8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              deviceName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: GlassTokens.displayFont,
                                fontSize: 21,
                                fontWeight: FontWeight.w700,
                                height: 1.1,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.edit_outlined,
                            size: 16,
                            color: Colors.white.withValues(alpha: 0.7),
                            semanticLabel: 'Rename',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$deviceId · $productType',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                    const SizedBox(height: 8),
                    isDirectMode
                        ? const StatusTag(
                            label: 'Direct connected',
                            color: GlassTokens.onGold,
                            showDot: true,
                            background: GlassTokens.gold,
                            foreground: GlassTokens.onGold,
                          )
                        : StatusTag(
                            label: isOnline ? 'Online' : 'Offline',
                            color: Colors.white,
                            showDot: true,
                            background: isOnline
                                ? GlassTokens.success
                                : GlassTokens.danger,
                            foreground: Colors.white,
                          ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Small translucent square button used in the header's top row. With no
/// [onTap] it is a plain indicator.
class _HeaderButton extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String tooltip;
  final VoidCallback? onTap;

  const _HeaderButton({
    required this.icon,
    this.iconColor = Colors.white,
    required this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(icon, color: iconColor, size: 22),
          ),
        ),
      ),
    );
  }
}
