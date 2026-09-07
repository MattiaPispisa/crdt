import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:flutter/material.dart';

import 'package:greyhound_markdown_client/src/config.dart';
import 'package:greyhound_markdown_client/src/l10n/l10n_extension.dart';
import 'package:greyhound_markdown_client/src/services/export/document_export.dart';

/// App-bar button that saves the room's document in a chosen format.
///
/// Picking a format opens a dialog with the name to give the file, filled in
/// from the document's first heading. On browsers with a save dialog of their
/// own the user then also picks the folder; elsewhere the file lands in the
/// downloads folder under that name.
///
/// The markdown is read at the moment the user picks a format, so the menu
/// itself only watches whether the document is empty — it stays put while the
/// room is being typed in. An empty document has nothing to export, so the
/// button is disabled until someone writes something.
class ExportMenu extends StatefulWidget {
  /// Creates an export menu.
  ///
  /// [fallbackName] names the file when the document has no heading to take a
  /// name from. [exporter] is for tests.
  const ExportMenu({required this.fallbackName, this.exporter, super.key});

  /// File name used when the document opens with no heading.
  final String fallbackName;

  /// The exporter to drive; a default one is built when omitted.
  final DocumentExporter? exporter;

  @override
  State<ExportMenu> createState() => _ExportMenuState();
}

class _ExportMenuState extends State<ExportMenu> {
  late final DocumentExporter _exporter =
      widget.exporter ?? DocumentExporter();

  /// True while a file is being rendered: a big document takes a moment, and
  /// a second tap would render it twice.
  bool _busy = false;

  Future<void> _export(ExportFormat format) async {
    final markdown = context
        .crdtHandler<CRDTFugueTextHandler>(kHandlerId)
        .value;
    final fileName = await showDialog<String>(
      context: context,
      builder: (context) => _ExportDialog(
        format: format,
        initialName: suggestedFileName(
          markdown,
          fallback: widget.fallbackName,
        ),
      ),
    );
    if (fileName == null || !mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    setState(() => _busy = true);
    try {
      final saved = await _exporter.export(
        markdown: markdown,
        format: format,
        fileName: fileName,
        languageCode: Localizations.localeOf(context).languageCode,
      );
      if (saved) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              l10n.exportSaved('$fileName.${format.extension}'),
            ),
          ),
        );
      }
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.exportFailed('$error'))),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return CrdtHandlerSelector<CRDTFugueTextHandler, bool>(
      id: kHandlerId,
      selector: (context, handler) => handler.value.isEmpty,
      builder: (context, isEmpty) => PopupMenuButton<ExportFormat>(
        tooltip: context.l10n.exportDocument,
        icon: const Icon(Icons.save_alt),
        enabled: !isEmpty && !_busy,
        onSelected: _export,
        itemBuilder: (context) => [
          for (final format in ExportFormat.values)
            PopupMenuItem<ExportFormat>(
              value: format,
              child: Text('${format.label} (.${format.extension})'),
            ),
        ],
      ),
    );
  }
}

/// Asks for the name to save the file under.
///
/// Returns the name without its extension, or `null` when the user backed
/// out. Whatever they type is cleaned the same way a heading is, so the
/// result is always a usable file name.
class _ExportDialog extends StatefulWidget {
  const _ExportDialog({required this.format, required this.initialName});

  final ExportFormat format;
  final String initialName;

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(
      context,
    ).pop(fileNameOf(_controller.text, fallback: widget.initialName));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.exportAs(widget.format.label)),
      content: TextField(
        controller: _controller,
        autofocus: true,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: context.l10n.exportFileName,
          suffixText: '.${widget.format.extension}',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(context.l10n.save)),
      ],
    );
  }
}
