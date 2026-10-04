import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/glass_theme.dart';
import '../widgets/glass/glass.dart';

// =============================================================================
// ABOUT  (UI v2)
// =============================================================================
// Forest card with the logo, then short rows: About us, Our mission, Our
// vision and Our values each open a sheet with the full text; the contact
// rows copy the address or number on tap. Same company text as before.
// =============================================================================

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

  static const String _aboutUs =
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
      'innovation.';

  static const String _mission =
      'To strengthen Sri Lanka\'s technological and economic growth '
      'by developing innovative, locally engineered IoT, '
      'automation, and AI solutions that reduce dependence on '
      'imported technologies while empowering businesses through '
      'smarter, more efficient operations.';

  static const String _vision =
      'To become a globally recognized leader in automation and '
      'intelligent technology, delivering sustainable, high-quality '
      'solutions that transform agriculture, industry, and everyday '
      'life through innovation developed in Sri Lanka.';

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        // Clear the translucent bottom nav this tab scrolls under.
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        // ── Logo card ──
        ForestHeader(
          coverStatusBar: false,
          radius: GlassTokens.radiusLg,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.4),
                    width: 2,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.asset(
                  'assets/images/logo.jpeg',
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.eco_outlined,
                    color: GlassTokens.primary,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'VorteX Labs',
                      style: TextStyle(
                        fontFamily: GlassTokens.displayFont,
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Automation and IoT, made in Sri Lanka',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ── Company ──
        SettingsGroup(
          children: [
            SettingsRow(
              icon: Icons.info_outline_rounded,
              iconColor: GlassTokens.primary,
              iconBackground: GlassTokens.leafSoft,
              title: 'About us',
              subtitle: 'Who we are',
              onTap: () => _showText(context, 'About us', _aboutUs),
            ),
            SettingsRow(
              icon: Icons.flag_outlined,
              iconColor: GlassTokens.sun,
              iconBackground: GlassTokens.sunSoft,
              title: 'Our mission',
              onTap: () => _showText(context, 'Our mission', _mission),
            ),
            SettingsRow(
              icon: Icons.visibility_outlined,
              iconColor: GlassTokens.water,
              iconBackground: GlassTokens.waterSoft,
              title: 'Our vision',
              onTap: () => _showText(context, 'Our vision', _vision),
            ),
            SettingsRow(
              icon: Icons.star_outline_rounded,
              iconColor: GlassTokens.info,
              iconBackground: GlassTokens.infoSoft,
              title: 'Our values',
              subtitle: '${_values.length} principles',
              onTap: () => _showValues(context),
            ),
          ],
        ),

        const SizedBox(height: 20),

        // ── Contact ──
        const SettingsLabel('Contact'),
        SettingsGroup(
          children: [
            for (final (icon, value) in const [
              (Icons.mail_outline_rounded, 'info@vortexlabsofficial.com'),
              (Icons.phone_outlined, '+94 70 554 9401'),
              (Icons.language_rounded, 'www.vortexlabsofficial.com'),
            ])
              SettingsRow(
                icon: icon,
                iconColor: GlassTokens.textSecondary,
                iconBackground: GlassTokens.sunk,
                title: value,
                showChevron: false,
                onTap: () => _copy(context, value),
              ),
          ],
        ),

        const SizedBox(height: 20),
        const Center(
          child: Text(
            '© 2025 Vortex Labs Official',
            style: TextStyle(color: GlassTokens.textMuted, fontSize: 12.5),
          ),
        ),
      ],
    );
  }

  static void _copy(BuildContext context, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied $value')),
    );
  }

  static Future<void> _showText(
    BuildContext context,
    String title,
    String body,
  ) {
    return _sheet(
      context,
      title,
      [
        Text(
          body,
          style: const TextStyle(
            fontSize: 14.5,
            height: 1.55,
            color: GlassTokens.textSecondary,
          ),
        ),
      ],
    );
  }

  static Future<void> _showValues(BuildContext context) {
    return _sheet(
      context,
      'Our values',
      [
        const Text(
          'At VorteX Labs, our work is guided by the principles that define '
          'who we are:',
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: GlassTokens.textSecondary,
          ),
        ),
        const SizedBox(height: 12),
        for (final v in _values)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.check_circle_outline_rounded,
                      size: 18, color: GlassTokens.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        v['title']!,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: GlassTokens.textPrimary,
                        ),
                      ),
                      Text(
                        v['body']!,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: GlassTokens.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Rounded bottom sheet with a drag handle and a title, scrollable.
  static Future<void> _sheet(
    BuildContext context,
    String title,
    List<Widget> children,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: GlassTokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            10,
            20,
            24 + MediaQuery.paddingOf(sheetContext).bottom,
          ),
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
              Text(
                title,
                style: const TextStyle(
                  fontFamily: GlassTokens.displayFont,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: GlassTokens.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}
