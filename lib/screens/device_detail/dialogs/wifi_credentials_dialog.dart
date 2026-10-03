import 'package:flutter/material.dart';

import '../../../services/esp_direct_service.dart';
import '../../../theme/glass_theme.dart';
import '../../../widgets/glass/glass.dart';
import '../../../utils/app_log.dart';

// =============================================================================
// WIFI CREDENTIALS DIALOG (Direct mode)
// =============================================================================
// Collects home WiFi SSID + password and sends set_valve_wifi to the connected
// ESP32. Architecture Doc Page 13. The ESP32 restarts afterwards, so the direct
// connection is expected to drop right after sending.
//
// [isSensorUnit] reuses the same sheet for the sensor unit, which has its own
// event: set_device_wifi (EspDirectService.setSensorUnitWifi). Only the event
// and the device word in the texts change.
//
// UI v2: a bottom sheet (same pattern as the add-slot sheet) with a short
// "what happens next" note. Sending, checks and messages are unchanged.
// =============================================================================

/// Delay before closing the dialog — gives the ESP32 time to store the
/// credentials before it restarts.
const Duration _restartGrace = Duration(seconds: 3);

Future<void> showWifiCredentialsDialog(
  BuildContext context, {
  bool isSensorUnit = false,
}) {
  final String device = isSensorUnit ? 'sensor unit' : 'valve';
  final ssidController = TextEditingController();
  final passwordController = TextEditingController();
  bool obscurePassword = true;
  bool isSending = false;

  // Captured up front so the success message still works after the dialog
  // (and its context) is gone.
  final messenger = ScaffoldMessenger.of(context);

  void showMessage(String message, {Color? color, Duration? duration}) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: duration ?? const Duration(seconds: 4),
      ),
    );
  }

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: GlassTokens.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) {
        void send() {
          final ssid = ssidController.text.trim();
          final password = passwordController.text;

          if (ssid.isEmpty) {
            showMessage('Please enter WiFi name');
            return;
          }

          if (!EspDirectService.instance.isAuthenticated) {
            showMessage(
              'Not connected to $device. Go back and reconnect.',
              color: GlassTokens.danger,
            );
            return;
          }

          setDialogState(() => isSending = true);

          if (isSensorUnit) {
            EspDirectService.instance.setSensorUnitWifi(
              ssid: ssid,
              password: password,
            );
            logD("📤 ESP32: set_device_wifi ssid=$ssid");
          } else {
            EspDirectService.instance.setWifiCredentials(
              ssid: ssid,
              password: password,
            );
            logD("📤 ESP32: set_valve_wifi ssid=$ssid");
          }

          // ESP32 will restart — the connection will be lost.
          Future.delayed(_restartGrace, () {
            if (!dialogContext.mounted) return;
            Navigator.pop(dialogContext);
            showMessage(
              isSensorUnit
                  ? 'WiFi credentials sent! Sensor unit will restart and connect to your home WiFi.'
                  : 'WiFi credentials sent! Valve will restart and connect to your home WiFi.',
              color: GlassTokens.success,
              duration: const Duration(seconds: 5),
            );
          });
        }

        return Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            10,
            18,
            18 +
                MediaQuery.viewInsetsOf(dialogContext).bottom +
                MediaQuery.paddingOf(dialogContext).bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                      color: GlassTokens.border,
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: GlassTokens.waterSoft,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(Icons.wifi, color: GlassTokens.water),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Set farm Wi-Fi',
                            style: TextStyle(
                              fontFamily: GlassTokens.displayFont,
                              fontSize: 21,
                              fontWeight: FontWeight.w700,
                              color: GlassTokens.textPrimary,
                            ),
                          ),
                          Text(
                            'The $device uses this to reach the internet',
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: GlassTokens.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: ssidController,
                  autofocus: true,
                  enabled: !isSending,
                  textInputAction: TextInputAction.next,
                  decoration: glassInputDecoration(
                    labelText: 'Wi-Fi name',
                    hintText: 'Enter your farm Wi-Fi name',
                    prefixIcon: const Icon(Icons.wifi),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  obscureText: obscurePassword,
                  enabled: !isSending,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => isSending ? null : send(),
                  decoration: glassInputDecoration(
                    labelText: 'Password',
                    hintText: 'Enter Wi-Fi password',
                    prefixIcon: const Icon(Icons.key_outlined),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscurePassword
                            ? Icons.visibility
                            : Icons.visibility_off,
                        color: GlassTokens.textMuted,
                      ),
                      onPressed: () {
                        setDialogState(
                            () => obscurePassword = !obscurePassword);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // What happens next
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: GlassTokens.sunk,
                    borderRadius: BorderRadius.circular(GlassTokens.radiusSm),
                  ),
                  child: Column(
                    children: [
                      _Step(1, 'The $device saves the name and password'),
                      const SizedBox(height: 6),
                      const _Step(
                          2, 'It restarts, so this direct link will drop'),
                      const SizedBox(height: 6),
                      const _Step(
                          3, 'It joins your farm Wi-Fi and appears online'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: isSending
                            ? null
                            : () => Navigator.pop(dialogContext),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: GlassButton(
                        label: isSending ? 'Sending…' : 'Save & connect',
                        icon: Icons.wifi,
                        height: 48,
                        isLoading: isSending,
                        onPressed: isSending ? null : send,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// One numbered line of the "what happens next" note.
class _Step extends StatelessWidget {
  final int n;
  final String text;

  const _Step(this.n, this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: GlassTokens.surface,
            shape: BoxShape.circle,
            border: Border.all(color: GlassTokens.border),
          ),
          child: Text(
            '$n',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: GlassTokens.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
