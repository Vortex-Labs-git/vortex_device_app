// =============================================================================
// GLASS UI KIT — barrel file
// =============================================================================
// One import for the whole frosted-glass kit:
//
//   import '../../widgets/glass/glass.dart';
//
// What's in here:
//   GlassBackground   the gradient + orb backdrop the panes blur (required —
//                     glass over nothing just looks grey)
//   GlassScaffold     Scaffold + backdrop, pre-wired for translucent chrome
//   GlassSurface      the base pane primitive
//   GlassCard         content-block preset of GlassSurface
//   GlassPill         small tinted capsule for statuses
//   GlassAppBar       translucent app bar
//   GlassBottomNav    translucent bottom navigation
//   GlassButton       solid gradient primary action
//   GlassGhostButton  pressable glass pane, secondary action
//   GlassFab          circular gradient action button
//   GlassDialog       glass dialog + showGlassDialog()
//   ForestHeader      forest brand band + ForestStat summary tiles (UI v2)
//   StatusTag         Online / Offline / Direct / type pills (UI v2)
//   SegmentedPicker   one-of-N switch, e.g. Manual | Schedule | Sensor (UI v2)
//
// Design tokens live in theme/glass_theme.dart.
// =============================================================================

export 'glass_app_bar.dart';
export 'glass_background.dart';
export 'glass_bottom_nav.dart';
export 'glass_button.dart';
export 'glass_dialog.dart';
export 'glass_scaffold.dart';
export 'glass_surface.dart';
export 'forest_header.dart';
export 'segmented_picker.dart';
export 'status_tag.dart';
