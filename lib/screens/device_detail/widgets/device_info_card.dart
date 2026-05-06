import 'package:flutter/material.dart';

class DeviceInfoCard extends StatelessWidget {
  final Map<String, dynamic> device;
  final bool isDirectMode;
  final bool isOnline;
  final VoidCallback onEditName;

  const DeviceInfoCard({
    super.key,
    required this.device,
    required this.isDirectMode,
    required this.isOnline,
    required this.onEditName,
  });

  @override
  Widget build(BuildContext context) {
    String statusText = isDirectMode ? 'Direct Connected' : (isOnline ? 'online' : 'offline');
    Color statusColor = isOnline ? Colors.green : Colors.red;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildInfoRow('Product Type', device['type'] ?? 'WiFi Valve v1'),
            const Divider(),
            _buildInfoRowWithEdit(
                'Name',
                device['vwv_name'] ?? device['device_name'] ?? 'Unknown',
                onEditName),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Connection Status',
                    style: TextStyle(color: Colors.grey)),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      statusText,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildInfoRowWithEdit(String label, String value, VoidCallback onEdit) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey)),
        Row(
          children: [
            TextButton(
              onPressed: onEdit,
              child: const Text('Edit', style: TextStyle(color: Colors.blue)),
            ),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
          ],
        ),
      ],
    );
  }
}