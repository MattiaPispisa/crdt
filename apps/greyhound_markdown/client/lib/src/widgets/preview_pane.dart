import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import 'package:greyhound_markdown_client/src/config.dart';

/// Rendered markdown preview; rebuilds only when the handler text changes.
class PreviewPane extends StatelessWidget {
  const PreviewPane({super.key});

  @override
  Widget build(BuildContext context) {
    return CrdtHandlerSelector<CRDTFugueTextHandler, String>(
      id: kHandlerId,
      selector: (context, handler) => handler.value,
      builder: (context, markdown) => Markdown(
        data: markdown,
        selectable: true,
        padding: const EdgeInsets.all(16),
      ),
    );
  }
}
