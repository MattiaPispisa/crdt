import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:flutter/material.dart';

import 'package:greyhound_markdown_client/src/config.dart';
import 'package:greyhound_markdown_client/src/services/document_export.dart';

/// App-bar button that downloads the room's document in a chosen format.
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
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await _exporter.export(
        markdown: markdown,
        format: format,
        fallbackName: widget.fallbackName,
      );
      messenger.showSnackBar(
        SnackBar(content: Text('Exported as ${format.label}')),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Export failed: $error')),
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
        tooltip: 'Export document',
        icon: const Icon(Icons.download_outlined),
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
