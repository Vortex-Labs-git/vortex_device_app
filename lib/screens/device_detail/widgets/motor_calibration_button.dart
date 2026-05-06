import 'package:flutter/material.dart';
import '../../motor_calibration_screen.dart';

class MotorCalibrationButton extends StatelessWidget {
  final Map<String, dynamic> deviceData;

  const MotorCalibrationButton({super.key, required this.deviceData});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => MotorCalibrationScreen(deviceData: deviceData),
            ),
          );
        },
        icon: const Icon(Icons.tune),
        label: const Text('Motor Calibration'),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF3F51B5),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          textStyle: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
}