import 'package:flutter/material.dart';
import '../../theme/glass_theme.dart';
import '../../utils/constants.dart';
import '../../widgets/glass/glass.dart';

// Tab screens
import '../home/home_screen.dart';
import '../user_screen.dart';
import '../about_screen.dart';
import '../manual_screen.dart';

// Local widgets
import 'widgets/main_app_bar.dart';
import 'widgets/main_bottom_nav.dart';

// =============================================================================
// MAIN SCREEN
// =============================================================================
// Top-level shell holding the 4 tabs (Home / User / Manual / About) inside an
// IndexedStack. Owns the current tab index, the add-device sheet (opened from
// the "+" in the bottom bar), and the navigation between tabs. Each tab screen below the IndexedStack manages
// its own state independently.
// =============================================================================

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  // ---------------------------------------------------------------------------
  // SECTION 1: STATE VARIABLES
  // ---------------------------------------------------------------------------

  // -- Current tab index (0=Home, 1=User, 2=Manual, 3=About) --
  int _currentIndex = 0;

  // -- Tab screens kept alive by IndexedStack --
  final List<Widget> _pages = [
    const HomeScreen(),
    const UserScreen(),
    const ManualScreen(),
    const AboutScreen(),
  ];

  // ---------------------------------------------------------------------------
  // SECTION 2: ADD DEVICE SHEET
  // ---------------------------------------------------------------------------
  // Triggered by the "+" in the bottom bar (hidden for now — see
  // MainBottomNav). Currently a placeholder — captures
  // a name and shows a snackbar. Real backend hookup is still pending.
  //
  // UI v2: a bottom sheet instead of a centred dialog (one-thumb reach). The
  // device-type picker is visual only for now; the name and the snackbar are
  // exactly what the old dialog did.

  void _showAddDeviceDialog(BuildContext context) {
    final nameController = TextEditingController();
    String type = 'VA';

    const types = <(String, String, IconData)>[
      ('VA', 'Valve', Icons.water_drop_outlined),
      ('SU', 'Sensor unit', Icons.sensors),
      ('SP', 'Smart plug', Icons.power_outlined),
    ];

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: GlassTokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            10,
            18,
            22 +
                MediaQuery.viewInsetsOf(sheetContext).bottom +
                MediaQuery.paddingOf(sheetContext).bottom,
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
              const SizedBox(height: 16),
              const Text(
                'Add a device',
                style: TextStyle(
                  fontFamily: GlassTokens.displayFont,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: GlassTokens.textPrimary,
                ),
              ),
              const Text(
                'What are you connecting?',
                style: TextStyle(fontSize: 13, color: GlassTokens.textMuted),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  for (final (code, label, icon) in types) ...[
                    if (code != types.first.$1) const SizedBox(width: 8),
                    Expanded(
                      child: _TypeOption(
                        label: label,
                        icon: icon,
                        selected: type == code,
                        onTap: () => setSheetState(() => type = code),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                autofocus: true,
                textInputAction: TextInputAction.done,
                decoration: glassInputDecoration(
                  labelText: 'Device name',
                  hintText: 'e.g. Main Valve',
                  prefixIcon: const Icon(Icons.label_outline),
                ),
              ),
              const SizedBox(height: 16),
              GlassButton(
                label: 'Add device',
                onPressed: () {
                  Navigator.pop(sheetContext);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Device "${nameController.text}" added!'),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SECTION 3: BUILD METHOD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Home draws its own forest header behind the status bar, so it gets no
    // app bar and no top SafeArea. The other tabs keep the plain app bar and
    // sit below it via SafeArea (with extendBodyBehindAppBar, the bar's height
    // is part of the top padding).
    final bool onHome = _currentIndex == 0;

    return GlassScaffold(
      useSafeArea: false,

      // 3.1  Top app bar on the non-Home tabs (person icon jumps to User tab)
      appBar: onHome
          ? null
          : MainAppBar(
              onPersonPressed: () => setState(() => _currentIndex = 1),
            ),

      // 3.2  Tab content (IndexedStack keeps all tabs alive)
      body: IndexedStack(
        index: _currentIndex,
        children: [
          for (int i = 0; i < _pages.length; i++)
            i == 0
                ? _pages[i]
                : SafeArea(top: true, bottom: false, child: _pages[i]),
        ],
      ),

      // 3.3  Bottom navigation (add-device "+" currently hidden)
      bottomNavigationBar: MainBottomNav(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        onAddPressed: () => _showAddDeviceDialog(context),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// One tappable device-type tile in the add-device sheet.
// -----------------------------------------------------------------------------

class _TypeOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _TypeOption({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color fg = selected ? GlassTokens.primary : GlassTokens.textPrimary;
    return Material(
      color: selected ? GlassTokens.leafSoft : GlassTokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(GlassTokens.radiusMd),
        side: BorderSide(
          color: selected ? GlassTokens.primary : GlassTokens.border,
          width: 1.5,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(GlassTokens.radiusMd),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          child: Column(
            children: [
              Icon(icon, color: fg, size: 26),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
