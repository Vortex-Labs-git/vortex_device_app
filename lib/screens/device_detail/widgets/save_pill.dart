import 'package:flutter/material.dart';

import '../../../theme/glass_theme.dart';

// =============================================================================
// SAVE PILL  (UI v2)
// =============================================================================
// The floating "Changes not saved · Save" pill for the Schedule and Sensor
// rules tabs (valve and plug). It slides up only while there is something to
// save ([hasUnsavedChanges]) or a save is running ([isSaving] — spinner and
// "Saving…"), and slides away when the server has it. The parent places it at
// the bottom of the screen (FloatingSavePill) and owns the save call.
// =============================================================================

/// Bottom-centred, animated wrapper: put it in the screen's Stack.
class FloatingSavePill extends StatelessWidget {
  final bool hasUnsavedChanges;
  final bool isSaving;
  final VoidCallback onSavePressed;

  const FloatingSavePill({
    super.key,
    required this.hasUnsavedChanges,
    required this.isSaving,
    required this.onSavePressed,
  });

  /// Space a list needs at its end so the pill never covers the last item.
  static const double reservedHeight = 76;

  bool get visible => hasUnsavedChanges || isSaving;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 16 + MediaQuery.paddingOf(context).bottom,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, 1.6),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: visible ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: Center(
              child: SavePill(isSaving: isSaving, onSavePressed: onSavePressed),
            ),
          ),
        ),
      ),
    );
  }
}

class SavePill extends StatelessWidget {
  final bool isSaving;
  final VoidCallback onSavePressed;

  const SavePill({
    super.key,
    required this.isSaving,
    required this.onSavePressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: GlassTokens.textPrimary,
      elevation: 8,
      shadowColor: Colors.black54,
      shape: const StadiumBorder(),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 6, isSaving ? 18 : 6, 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSaving)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: GlassTokens.gold,
                ),
              )
            else
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: GlassTokens.gold,
                  shape: BoxShape.circle,
                ),
              ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                isSaving ? 'Saving…' : 'Changes not saved',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
            if (!isSaving) ...[
              const SizedBox(width: 12),
              Material(
                color: GlassTokens.gold,
                shape: const StadiumBorder(),
                child: InkWell(
                  onTap: onSavePressed,
                  customBorder: const StadiumBorder(),
                  child: const Padding(
                    padding:
                        EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                    child: Text(
                      'Save',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: GlassTokens.onGold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
