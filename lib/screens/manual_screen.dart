import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/glass_theme.dart';
import '../widgets/glass/glass.dart';

// =============================================================================
// GUIDE (user manual)  (UI v2)
// =============================================================================
// The Guide tab: a search box and one card per topic. Tapping a card opens a
// short page of numbered steps, bullets and tips (_GuideTopicPage). The text
// follows the UI v2 screens and covers the valve, sensor unit and smart plug.
// Search matches topic titles and their text. Contact rows copy on tap.
// =============================================================================

// -----------------------------------------------------------------------------
// Content
// -----------------------------------------------------------------------------

sealed class _Block {
  const _Block();
  String get text;
}

class _Heading extends _Block {
  @override
  final String text;
  const _Heading(this.text);
}

class _Steps extends _Block {
  final List<String> items;
  const _Steps(this.items);
  @override
  String get text => items.join(' ');
}

class _Bullets extends _Block {
  final List<String> items;
  const _Bullets(this.items);
  @override
  String get text => items.join(' ');
}

class _Tip extends _Block {
  @override
  final String text;
  const _Tip(this.text);
}

class _Contact extends _Block {
  final IconData icon;
  final String value;
  const _Contact(this.icon, this.value);
  @override
  String get text => value;
}

class _Topic {
  final IconData icon;
  final Color color;
  final Color background;
  final String title;
  final String summary;
  final List<_Block> blocks;

  const _Topic({
    required this.icon,
    required this.color,
    required this.background,
    required this.title,
    required this.summary,
    required this.blocks,
  });

  bool matches(String query) {
    final q = query.toLowerCase();
    return title.toLowerCase().contains(q) ||
        summary.toLowerCase().contains(q) ||
        blocks.any((b) => b.text.toLowerCase().contains(q));
  }
}

const Color _purple = GlassTokens.info;
const Color _purpleSoft = Color(0xFFEFE7FC);
const Color _redSoft = Color(0xFFFBE6E6);

const List<_Topic> _topics = [
  _Topic(
    icon: Icons.play_circle_outline_rounded,
    color: GlassTokens.primary,
    background: GlassTokens.leafSoft,
    title: 'Getting started',
    summary: 'Log in, Home, device cards',
    blocks: [
      _Steps([
        'Open the Vortex Labs app and log in with your username and password.',
        'Home shows every device on your account: valves, sensor units and smart plugs.',
        'Each card shows the name, ID and status: Online, Offline or Direct connected (gold).',
        'Use the chips on Home to show one kind of device. Pull down to refresh the list.',
        'Tap a card to open the device.',
      ]),
      _Tip('No devices? Contact Vortex Labs to add your devices to your account.'),
    ],
  ),
  _Topic(
    icon: Icons.settings_input_antenna_rounded,
    color: GlassTokens.sun,
    background: GlassTokens.goldSoft,
    title: 'Cloud & direct link',
    summary: 'Online vs the device hotspot',
    blocks: [
      _Heading('Cloud (normal)'),
      _Bullets([
        'The device is on your farm Wi-Fi and talks to the app through the Vortex cloud.',
        'You can control it from anywhere.',
        'Schedules and sensor rules need this connection.',
      ]),
      _Heading('Direct link'),
      _Bullets([
        'When a device has no internet, it makes its own Wi-Fi hotspot named "Vortex_" plus its ID, for example "Vortex_VA202601001".',
        "Connect your phone to that hotspot in your phone's Wi-Fi settings, then open the app.",
        'The card shows "Direct connected" and the device screen turns gold.',
        'Only manual control works here: open / close a valve, or switch a plug ON / OFF.',
      ]),
      _Tip('The app switches back to the cloud by itself when your phone rejoins your normal Wi-Fi.'),
    ],
  ),
  _Topic(
    icon: Icons.water_drop_outlined,
    color: GlassTokens.water,
    background: GlassTokens.waterSoft,
    title: 'Motorized valve',
    summary: 'Open, close, angle, schedule',
    blocks: [
      _Heading('Open and close'),
      _Steps([
        'Open the valve and stay on the Control tab.',
        'Tap "Open valve" or "Close valve".',
        '"Valve now" shows the position the valve reports. Wait a few seconds for it to confirm.',
      ]),
      _Heading('Set a part-open angle'),
      _Steps([
        'Open "Advanced" on the Control tab.',
        'Drag the slider between 0° and 90°. The picture shows the lever: solid is where it is now, dashed is where it will go.',
        'Tap "Set valve to …°".',
      ]),
      _Heading('Manual or Automatic'),
      _Bullets([
        '"Valve runs on" switches between Manual and Automatic.',
        'In Automatic, turn on Schedule, Sensor or both. While it runs, only that tab can be opened.',
      ]),
      _Heading('Schedule'),
      _Steps([
        'Open the Schedule tab and tap "+ Add slot".',
        'Pick the day, From and To, and Close / Open (or an angle under Advanced).',
        'Tap Save in the dark pill at the bottom.',
      ]),
      _Tip('Valve schedules are kept to the minute; seconds are not saved.'),
      _Heading('Sensor rules'),
      _Steps([
        'Open the Sensor rules tab and tap "Choose a sensor": pick a sensor unit, then a sensor.',
        'Tap "+ Add rule": enter the reading range and where the valve should go.',
        'Tap Save in the pill. The rule that matches the current reading shows "In use now".',
      ]),
      _Heading('Direct link tools'),
      _Bullets([
        'Change Wi-Fi: send your farm Wi-Fi to the valve.',
        'Motor calibration: set the fully closed and fully open points.',
      ]),
    ],
  ),
  _Topic(
    icon: Icons.sensors_rounded,
    color: _purple,
    background: _purpleSoft,
    title: 'Sensor unit',
    summary: 'Readings and sensor setup',
    blocks: [
      _Bullets([
        'Each tile shows a sensor: its tag name, the value, its type and slot (S01 to S08).',
        'If the unit is offline, a red note says when it was last seen and the values are blurred.',
        'On the direct link, values update every 2 seconds.',
      ]),
      _Heading('Sensor configuration (direct link)'),
      _Steps([
        'Connect to the unit\'s hotspot and open it, then tap "Sensor configuration".',
        'Sensor 01 and 02 are built in. Tap any other slot to choose its type and tag name.',
        'Tap "Save to unit". The unit restarts with the new setup.',
      ]),
    ],
  ),
  _Topic(
    icon: Icons.power_settings_new_rounded,
    color: GlassTokens.primary,
    background: GlassTokens.leafSoft,
    title: 'Smart plug',
    summary: 'Sockets, ON / OFF, rules',
    blocks: [
      _Heading('Switch a socket'),
      _Steps([
        'Tap the socket card you want (a dual plug has two).',
        'On the Control tab, tap the big power button.',
        'Wait a moment while the plug confirms ON or OFF.',
      ]),
      _Heading('Turn ON at set times'),
      _Steps([
        'Open the Schedule tab and tap "+ Add time".',
        'Pick one day, then From and To (with seconds).',
        'To switch ON and OFF in a cycle, open "Advanced" and enter the ON and OFF seconds.',
        'Tap Save in the pill at the bottom.',
      ]),
      _Heading('Sensor rules'),
      _Steps([
        'Open the Sensor rules tab and tap "Choose a sensor".',
        'Tap "+ Add rule": enter the reading range and choose Turn ON or Turn OFF.',
        'Tap Save in the pill.',
      ]),
      _Tip('Each socket has its own schedule, sensor and rules.'),
    ],
  ),
  _Topic(
    icon: Icons.wifi_rounded,
    color: GlassTokens.water,
    background: GlassTokens.waterSoft,
    title: 'Wi-Fi setup',
    summary: 'Send farm Wi-Fi to a device',
    blocks: [
      _Steps([
        'Connect your phone to the device\'s hotspot ("Vortex_" plus its ID).',
        'Open the app and tap the device (it shows "Direct connected").',
        'Under Device tools, tap "Change Wi-Fi".',
        'Enter your farm Wi-Fi name and password, then tap "Save & connect".',
        'The device restarts, joins your Wi-Fi and shows Online in the app.',
      ]),
      _Tip('Afterwards, reconnect your phone to your normal Wi-Fi.'),
    ],
  ),
  _Topic(
    icon: Icons.build_outlined,
    color: GlassTokens.danger,
    background: _redSoft,
    title: 'Troubleshooting',
    summary: 'Offline, no reply, no devices',
    blocks: [
      _Heading('A device shows "Offline"'),
      _Bullets([
        'Check that the device has power.',
        'Check that it is connected to your Wi-Fi.',
        'Pull down on Home to refresh the list.',
      ]),
      _Heading('Cannot connect directly'),
      _Bullets([
        "Make sure your phone is on the device's hotspot.",
        'A device makes its hotspot only when it has no Wi-Fi set, or cannot reach its saved Wi-Fi.',
        'Stay within about 10 to 20 metres of the device.',
      ]),
      _Heading('A device does not respond'),
      _Bullets([
        'Wait a few seconds; the app waits for the device to confirm.',
        'Check "Valve now" on a valve, or the socket card on a plug.',
        'If it still does not respond, turn the device off and on again.',
      ]),
      _Heading('Home says "Offline — showing cached devices"'),
      _Bullets([
        'Your phone may have no internet, or the Vortex cloud may be briefly unreachable.',
        'You can still see your devices; control needs a live connection.',
      ]),
    ],
  ),
  _Topic(
    icon: Icons.support_agent_rounded,
    color: GlassTokens.textSecondary,
    background: GlassTokens.sunk,
    title: 'Contact & support',
    summary: 'Email, phone, website',
    blocks: [
      _Contact(Icons.mail_outline_rounded, 'info@vortexlabsofficial.com'),
      _Contact(Icons.phone_outlined, '+94 70 554 9401'),
      _Contact(Icons.language_rounded, 'www.vortexlabsofficial.com'),
      _Tip('Tap a contact to copy it.'),
    ],
  ),
];

// -----------------------------------------------------------------------------
// Guide tab
// -----------------------------------------------------------------------------

class ManualScreen extends StatefulWidget {
  const ManualScreen({super.key});

  @override
  State<ManualScreen> createState() => _ManualScreenState();
}

class _ManualScreenState extends State<ManualScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final String q = _query.trim();
    final topics =
        q.isEmpty ? _topics : _topics.where((t) => t.matches(q)).toList();

    return ListView(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        // Clear the translucent bottom nav this tab scrolls under.
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        const Text(
          'Guide',
          style: TextStyle(
            fontFamily: GlassTokens.displayFont,
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: GlassTokens.textPrimary,
          ),
        ),
        const Text(
          'How to use your Vortex devices',
          style: TextStyle(fontSize: 13, color: GlassTokens.textMuted),
        ),
        const SizedBox(height: 14),
        TextField(
          onChanged: (v) => setState(() => _query = v),
          textInputAction: TextInputAction.search,
          decoration: glassInputDecoration(
            hintText: 'Search the guide',
            prefixIcon: const Icon(Icons.search_rounded),
          ),
        ),
        const SizedBox(height: 14),
        if (topics.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Text(
              'Nothing found for "$q".',
              textAlign: TextAlign.center,
              style: const TextStyle(color: GlassTokens.textMuted),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              const double gap = 10;
              final double w = (constraints.maxWidth - gap) / 2;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final t in topics)
                    SizedBox(width: w, child: _TopicCard(topic: t)),
                ],
              );
            },
          ),
        const SizedBox(height: 24),
        const Center(
          child: Text(
            '© 2025 Vortex Labs Official',
            style: TextStyle(color: GlassTokens.textMuted, fontSize: 12.5),
          ),
        ),
      ],
    );
  }
}

class _TopicCard extends StatelessWidget {
  final _Topic topic;

  const _TopicCard({required this.topic});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(GlassTokens.radiusMd);
    return Material(
      color: GlassTokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: const BorderSide(color: GlassTokens.border),
      ),
      child: InkWell(
        borderRadius: radius,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => _GuideTopicPage(topic: topic)),
        ),
        child: SizedBox(
          height: 128,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(11, 12, 8, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: topic.background,
                    borderRadius: BorderRadius.circular(GlassTokens.radiusSm),
                  ),
                  child: Icon(topic.icon, color: topic.color, size: 21),
                ),
                const Spacer(),
                Text(
                  topic.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                    color: GlassTokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  topic.summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.3,
                    color: GlassTokens.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// One topic
// -----------------------------------------------------------------------------

class _GuideTopicPage extends StatelessWidget {
  final _Topic topic;

  const _GuideTopicPage({required this.topic});

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      appBar: GlassAppBar(title: topic.title, subtitle: 'Guide'),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          12,
          16,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          for (final b in topic.blocks) _buildBlock(context, b),
        ],
      ),
    );
  }

  Widget _buildBlock(BuildContext context, _Block b) {
    switch (b) {
      case _Heading():
        return Padding(
          padding: const EdgeInsets.fromLTRB(2, 10, 2, 8),
          child: Text(
            b.text,
            style: const TextStyle(
              fontFamily: GlassTokens.displayFont,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: GlassTokens.textPrimary,
            ),
          ),
        );
      case _Steps():
        return _card(
          Column(
            children: [
              for (int i = 0; i < b.items.length; i++)
                _line(
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: GlassTokens.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  b.items[i],
                  last: i == b.items.length - 1,
                ),
            ],
          ),
        );
      case _Bullets():
        return _card(
          Column(
            children: [
              for (int i = 0; i < b.items.length; i++)
                _line(
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Icon(Icons.circle,
                        size: 7, color: GlassTokens.primary),
                  ),
                  b.items[i],
                  last: i == b.items.length - 1,
                ),
            ],
          ),
        );
      case _Tip():
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: GlassTokens.goldSoft,
            borderRadius: BorderRadius.circular(GlassTokens.radiusSm),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.lightbulb_outline_rounded,
                  size: 18, color: GlassTokens.onGold),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  b.text,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: GlassTokens.onGold,
                  ),
                ),
              ),
            ],
          ),
        );
      case _Contact():
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SettingsGroup(
            children: [
              SettingsRow(
                icon: b.icon,
                iconColor: GlassTokens.primary,
                iconBackground: GlassTokens.leafSoft,
                title: b.value,
                showChevron: false,
                onTap: () => _copy(context, b.value),
              ),
            ],
          ),
        );
    }
  }

  static void _copy(BuildContext context, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied $value')),
    );
  }

  Widget _card(Widget child) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: GlassTokens.surface,
        borderRadius: BorderRadius.circular(GlassTokens.radiusMd),
        border: Border.all(color: GlassTokens.border),
      ),
      child: child,
    );
  }

  Widget _line(Widget lead, String text, {required bool last}) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          lead,
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.45,
                color: GlassTokens.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
