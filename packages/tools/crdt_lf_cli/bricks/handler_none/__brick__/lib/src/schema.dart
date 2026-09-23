import 'package:crdt_lf/crdt_lf.dart';

/// The id of the document the server holds and every client edits.
const documentId = '{{name}}';

/// Opens the handlers of [document].
///
/// Client and server both call it, so they agree on what the document holds.
/// Calling it again on the same document is safe: `document.handler` returns
/// the handler that is already open.
///
/// There are no handlers yet. Add one like this:
///
/// ```dart
/// document.handler(CRDTFugueTextHandler.spec, 'text');
/// ```
void openHandlers(CRDTDocument document) {}
