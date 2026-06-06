import 'package:crdt_lf_devtools_extension/src/presentation/ui/widgets/documents/document_selector.dart';
import 'package:flutter/material.dart';

/// Toolbar showing the document selector.
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
        ],
      ),
    );
  }
}
