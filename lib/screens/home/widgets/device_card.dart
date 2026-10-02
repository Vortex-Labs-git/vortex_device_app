import 'package:flutter/material.dart';

import '../../../theme/glass_theme.dart';
import '../../../widgets/glass/glass.dart';

// =============================================================================
// DEVICE CARD
// =============================================================================
// One device row in the home device list (UI v2): product photo tile with a
// status dot, name, "ID · last seen", a status tag and a device-type tag, and
// a chevron. The whole card is tappable — the parent decides what to do based
// on device status.
//
// Offline devices fade their photo to grey, so a stale device reads as stale
// before any text is read.
//
// Avatar logic (driven by the device ID prefix, see [_productImages]):
//   - VA*  → valve product image       (assets/images/VA_3.jpeg)
//   - SU*  → sensor unit product image (assets/images/SU_1.jpeg)
//   - SP*  → smart plug product image  (assets/images/SP_1.jpeg)
//   - else → neutral unknown-device icon
// If an image file is missing or fails to load, the card falls back to that
// device type's icon instead of showing an error box.
//
// All status logic (online / offline / esp_connected) lives in the parent;
// this widget just receives the resolved [statusText] / [statusColor] values,
// the direct-connection flag, and (optionally) the offline flag and the
// "last seen" line.
// =============================================================================

class DeviceCard extends StatelessWidget {
  final Map<String, dynamic> device;
  final String statusText; // "Online" | "Offline" | "Direct Connected"
  final Color statusColor; // Green or red
  final bool isEspConnected; // Direct AP link — gold tag and dot
  final VoidCallback onTap;

  /// Greys out the product photo. Defaults to false.
  final bool isOffline;

  /// Line after the ID, e.g. "Updated 3 s ago". Omitted when null.
  final String? subtitle;

  const DeviceCard({
    super.key,
    required this.device,
    required this.statusText,
    required this.statusColor,
    required this.isEspConnected,
    required this.onTap,
    this.isOffline = false,
    this.subtitle,
  });

  /// Product photo per ID prefix. Files live in assets/images/ (the whole
  /// folder is already registered in pubspec.yaml). Change a file name or
  /// extension here only.
  static const Map<String, String> _productImages = {
    'VA': 'assets/images/VA_3.jpeg',
    'SU': 'assets/images/SU_1.jpeg',
    'SP': 'assets/images/SP_1.jpeg',
  };

  /// Type tag per ID prefix: label, icon and category colour.
  static const Map<String, (String, IconData, Color)> _types = {
    'VA': ('Valve', Icons.water_drop_outlined, GlassTokens.water),
    'SU': ('Sensor unit', Icons.sensors, GlassTokens.info),
    'SP': ('Smart plug', Icons.power_outlined, GlassTokens.sun),
  };

  /// Desaturates the photo of an offline device.
  static const ColorFilter _greyscale = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0, 0, 0, 0.75, 0, //
  ]);

  @override
  Widget build(BuildContext context) {
    final String name =
        device['name'] ??
        device['vwv_name'] ??
        device['device_name'] ??
        'Unknown Device';
    final String id = device['id']?.toString() ?? '';
    final String idPrefix = id.toUpperCase();
    final String typePrefix =
        idPrefix.length >= 2 ? idPrefix.substring(0, 2) : idPrefix;
    final String? imagePath = _productImages[typePrefix];
    final (String, IconData, Color)? type = _types[typePrefix];

    // Dot on the photo: gold for a direct AP link (a different kind of
    // "connected" — no cloud, manual control only), else the status colour.
    final Color dot = isEspConnected ? GlassTokens.gold : statusColor;

    Widget photo = imagePath != null
        ? Image.asset(
            imagePath,
            width: 58,
            height: 58,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _fallbackIcon(type),
          )
        : _fallbackIcon(type);
    if (isOffline) photo = ColorFiltered(colorFilter: _greyscale, child: photo);

    return GlassSurface(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      borderRadius: BorderRadius.circular(GlassTokens.radiusLg),
      onTap: onTap,
      child: Row(
        children: [
          // ─────────────────────────────────────────────────────────────
          // Photo tile with the status dot on its corner
          // ─────────────────────────────────────────────────────────────
          SizedBox(
            width: 62,
            height: 62,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: GlassTokens.sunk,
                    borderRadius: BorderRadius.circular(GlassTokens.radiusMd),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: photo,
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 17,
                    height: 17,
                    decoration: BoxDecoration(
                      color: dot,
                      shape: BoxShape.circle,
                      border: Border.all(color: GlassTokens.surface, width: 3),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          // ─────────────────────────────────────────────────────────────
          // Name, ID · last seen, tags
          // ─────────────────────────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15.5,
                    color: GlassTokens.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle == null ? id : '$id · $subtitle',
                  style: const TextStyle(
                    color: GlassTokens.textMuted,
                    fontSize: 12,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    isEspConnected
                        ? StatusTag.direct(label: statusText)
                        : StatusTag(
                            label: statusText,
                            color: statusColor,
                            showDot: true,
                          ),
                    if (type != null)
                      StatusTag(label: type.$1, icon: type.$2, color: type.$3),
                  ],
                ),
              ],
            ),
          ),

          const Icon(
            Icons.chevron_right_rounded,
            color: GlassTokens.textMuted,
          ),
        ],
      ),
    );
  }

  /// The device-type icon, centred in the photo tile.
  Widget _fallbackIcon((String, IconData, Color)? type) {
    return Center(
      child: Icon(
        type?.$2 ?? Icons.device_unknown,
        size: 30,
        color: type?.$3 ?? GlassTokens.textMuted,
      ),
    );
  }
}
