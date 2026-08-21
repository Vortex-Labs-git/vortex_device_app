import 'package:flutter/material.dart';

import '../../../theme/glass_theme.dart';
import '../../../widgets/glass/glass.dart';

// =============================================================================
// EDIT DEVICE NAME DIALOG
// =============================================================================
// Prompts for a new device name and calls [onSave] with it. The dialog owns the
// saving spinner: it stays open (and re-enables the button) when [onSave]
// returns false, and closes returning the new name when it returns true.
//
// The TextEditingController is owned by this dialog's State. It must not be
// created beside the show() call and disposed with .whenComplete(): the route
// future completes the moment Navigator.pop runs, while the dialog is still
// rebuilding through its closing animation, so disposing there pulls the
// controller out from under a live TextField and throws "A
// TextEditingController was used after being disposed". State.dispose only runs
// once the widget is really gone, which is the correct moment — and unlike
// dropping the dispose altogether, it does not leak a controller per open.
// =============================================================================

/// Shows the rename dialog. Returns the saved name, or null if the user
/// cancelled or the save failed.
Future<String?> showEditDeviceNameDialog(
  BuildContext context, {
  required String? currentName,
  required Future<bool> Function(String newName) onSave,
}) {
  return showGlassDialog<String>(
    context: context,
    builder: (_) => _EditDeviceNameDialog(
      currentName: currentName,
      onSave: onSave,
    ),
  );
}

class _EditDeviceNameDialog extends StatefulWidget {
  final String? currentName;
  final Future<bool> Function(String newName) onSave;

  const _EditDeviceNameDialog({
    required this.currentName,
    required this.onSave,
  });

  @override
  State<_EditDeviceNameDialog> createState() => _EditDeviceNameDialogState();
}

class _EditDeviceNameDialogState extends State<_EditDeviceNameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.currentName);
  bool _isSaving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final String newName = _controller.text.trim();
    if (newName.isEmpty) return;

    setState(() => _isSaving = true);

    final bool success = await widget.onSave(newName);
    if (!mounted) return;

    if (success) {
      Navigator.pop(context, newName);
    } else {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassDialog(
      title: 'Edit Device Name',
      icon: Icons.drive_file_rename_outline,
      content: TextField(
        controller: _controller,
        autofocus: true,
        enabled: !_isSaving,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _isSaving ? null : _save(),
        decoration: glassInputDecoration(
          labelText: 'Device Name',
          prefixIcon: const Icon(Icons.label_outline),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        GlassButton(
          label: 'Save',
          fullWidth: false,
          height: 44,
          isLoading: _isSaving,
          onPressed: _isSaving ? null : _save,
        ),
      ],
    );
  }
}