import 'package:flutter/material.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const List<Map<String, String>> _values = [
    {
      'title': 'Innovation',
      'body':
          'Continuously developing smarter technologies to solve real-world challenges.',
    },
    {
      'title': 'Engineering Excellence',
      'body':
          'Building reliable, high-quality products with precision and performance.',
    },
    {
      'title': 'Local Empowerment',
      'body':
          'Supporting Sri Lanka\'s technological independence through locally developed solutions.',
    },
    {
      'title': 'Customer Success',
      'body':
          'Designing solutions that create measurable value for our customers.',
    },
    {
      'title': 'Sustainability',
      'body':
          'Developing technologies that promote efficient use of resources and long-term environmental responsibility.',
    },
    {
      'title': 'Integrity',
      'body':
          'Conducting business with honesty, transparency, and accountability.',
    },
    {
      'title': 'Versatility',
      'body':
          'Adapting our expertise to meet the evolving needs of agriculture, industry, and emerging technologies.',
    },
    {
      'title': 'Continuous Improvement',
      'body':
          'Learning, innovating, and evolving to stay ahead in a rapidly changing technological landscape.',
    },
  ];

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

            // ── Logo ──
            Center(
              child: ClipOval(
                child: Image.asset(
                  'assets/images/logo.jpeg',
                  width: 160,
                  height: 160,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    width: 160,
                    height: 160,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE0E0E8),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Text(
                        'logo',
                        style: TextStyle(fontSize: 18, color: Colors.black87),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 28),

            // ── About Us Card ──
            _buildCard(
              icon: Icons.info_outline,
              title: 'About Us',
              body:
                  'VorteX Labs is an innovation-driven technology company based '
                  'in Sri Lanka, dedicated to developing intelligent automation '
                  'and IoT solutions for agriculture, industry, and beyond. We '
                  'build integrated hardware and software platforms that '
                  'simplify monitoring, control, and automation, helping '
                  'businesses operate more efficiently and intelligently.\n\n'
                  'With expertise spanning IoT, artificial intelligence, '
                  'embedded systems, PCB design and manufacturing, 3D printing, '
                  'and custom software development, we deliver scalable, '
                  'locally engineered solutions designed to meet the evolving '
                  'needs of modern industries while driving technological '
                  'innovation.',
            ),

            const SizedBox(height: 20),

            // ── Our Mission Card ──
            _buildCard(
              icon: Icons.build_outlined,
              title: 'Our Mission',
              body:
                  'To strengthen Sri Lanka\'s technological and economic growth '
                  'by developing innovative, locally engineered IoT, '
                  'automation, and AI solutions that reduce dependence on '
                  'imported technologies while empowering businesses through '
                  'smarter, more efficient operations.',
            ),

            const SizedBox(height: 20),

            // ── Our Vision Card ──
            _buildCard(
              icon: Icons.thumb_up_outlined,
              title: 'Our Vision',
              body:
                  'To become a globally recognized leader in automation and '
                  'intelligent technology, delivering sustainable, high-quality '
                  'solutions that transform agriculture, industry, and everyday '
                  'life through innovation developed in Sri Lanka.',
            ),

            const SizedBox(height: 20),

            // ── Our Values Card ──
            _buildValuesCard(),

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

  Widget _buildValuesCard() {
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
            children: const [
              Icon(Icons.star_outline, color: Color(0xFF3F51B5), size: 28),
              SizedBox(width: 12),
              Text(
                'Our Values',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF3F51B5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'At VorteX Labs, our work is guided by the principles that define '
            'who we are:',
            style: TextStyle(
              fontSize: 15,
              color: Color(0xFF444444),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          ..._values.map(
            (v) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 7),
                    child: Icon(
                      Icons.circle,
                      size: 6,
                      color: Color(0xFF3F51B5),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          fontSize: 15,
                          color: Color(0xFF444444),
                          height: 1.5,
                        ),
                        children: [
                          TextSpan(
                            text: '${v['title']} – ',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF333333),
                            ),
                          ),
                          TextSpan(text: v['body']),
                        ],
                      ),
                    ),
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