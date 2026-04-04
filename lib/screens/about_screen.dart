import 'package:flutter/material.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),

            // ── About Us Card ──
            _buildCard(
              icon: Icons.info_outline,
              title: 'About Us',
              body:
                  'Vortex Labs specializes in cutting-edge automation and AI '
                  'solutions for agriculture and industry. Our flagship product, the '
                  'Vortex Smart Valve, is an IoT-enabled valve with sensor '
                  'integration capabilities. We also offer services in 3D printing, '
                  'PCB manufacturing, CAD design, website creation and hosting, '
                  'and custom vending machine development.',
            ),

            const SizedBox(height: 20),

            // ── Our Mission Card ──
            _buildCard(
              icon: Icons.build_outlined,
              title: 'Our Mission',
              body:
                  'Our mission is to uplift Sri Lanka\'s economy by advancing the '
                  'local production industry through IoT and related technologies, '
                  'reducing the need for imports.',
            ),

            const SizedBox(height: 20),

            // ── Our Vision Card ──
            _buildCard(
              icon: Icons.thumb_up_outlined,
              title: 'Our Vision',
              body:
                  'To become a leading force in technological innovation, '
                  'empowering Sri Lanka and beyond through sustainable, '
                  'locally-developed automation and AI solutions that drive '
                  'self-reliance and industrial growth.',
            ),

            const SizedBox(height: 20),

            // ── Our Values Card ──
            _buildCard(
              icon: Icons.star_outline,
              title: 'Our Values',
              body:
                  'Innovation, Local empowerment, Technical excellence, '
                  'Versatility, Sustainability, Integrity, Customer focus, '
                  'Engineering-driven leadership.',
            ),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildCard({
    required IconData icon,
    required String title,
    required String body,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5FA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE0E0E8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF3F51B5), size: 28),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF3F51B5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            body,
            style: const TextStyle(
              fontSize: 15,
              color: Color(0xFF444444),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}