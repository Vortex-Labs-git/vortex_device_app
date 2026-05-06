import 'package:flutter/material.dart';

class DeviceAppBar extends StatelessWidget implements PreferredSizeWidget {
  final bool isDirectMode;
  final bool wsConnected;

  const DeviceAppBar({
    super.key,
    required this.isDirectMode,
    required this.wsConnected,
  });

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text(isDirectMode ? 'Direct Control' : 'Vortex Labs'),
      backgroundColor: isDirectMode ? Colors.green[700] : const Color(0xFF3F51B5),
      foregroundColor: Colors.white,
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Icon(
            wsConnected
                ? (isDirectMode ? Icons.settings_remote : Icons.wifi)
                : Icons.wifi_off,
            color: wsConnected ? Colors.greenAccent : Colors.red,
          ),
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}