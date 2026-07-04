import 'package:flutter/material.dart';

/// A small dialog that collects a single line of text and reports it via
/// [onAdd]. Shared by the example documents to add a new item.
class AddItemDialog extends StatefulWidget {
  /// Creates an add-item dialog.
  const AddItemDialog({
    super.key,
    required this.onAdd,
    this.title = 'Add New Todo',
    this.hint = 'Enter todo text',
  });

  /// Called with the trimmed text when the user confirms (non-empty only).
  final void Function(String text) onAdd;

  /// The dialog title.
  final String title;

  /// The text field hint.
  final String hint;

  @override
  State<AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends State<AddItemDialog> {
  late TextEditingController controller;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _addAndPop() {
    if (controller.text.trim().isNotEmpty) {
      widget.onAdd(controller.text.trim());
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(hintText: widget.hint),
        onSubmitted: (_) => _addAndPop(),
      ),
      actions: <Widget>[
        TextButton(
          child: const Text('Cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        TextButton(onPressed: _addAndPop, child: const Text('Add')),
      ],
    );
  }
}
