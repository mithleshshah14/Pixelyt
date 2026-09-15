import 'package:flutter/material.dart';

/// Prompts for a filename, pre-filled with a sensible default; returns null
/// if cancelled, or the (possibly unmodified) name if confirmed.
class SaveNameDialog extends StatefulWidget {
  final String defaultName;
  final String title;
  final String confirmLabel;

  const SaveNameDialog({
    super.key,
    required this.defaultName,
    this.title = 'Save as',
    this.confirmLabel = 'Save',
  });

  @override
  State<SaveNameDialog> createState() => _SaveNameDialogState();
}

class _SaveNameDialogState extends State<SaveNameDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.defaultName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          helperText: 'Leave as-is to keep this name',
        ),
        onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
