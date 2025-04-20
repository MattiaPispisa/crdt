import 'package:crdt_lf_devtools_extension/src/presentation/ui/widgets/documents/document_selector.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/ui/widgets/documents/reload.dart';
import 'package:flutter/material.dart';

/// Toolbar for the documents
///
/// This toolbar contains a document selector and a reload button.
class DocumentsToolbar extends StatelessWidget {
  const DocumentsToolbar({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(16.0),
      child: Row(
        children: [
          Text('Document:'),
          SizedBox(width: 12),
          DocumentSelector(),
          SizedBox(width: 24),
          DocumentsReloadButton(),
        ],
      ),
    );
  }
}
