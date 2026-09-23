import 'package:crdt_lf/crdt_lf.dart';

/// The id of the document the server holds and every client edits.
const documentId = '{{name}}';

/// The id of the text handler.
const textHandlerId = 'text';

/// The collaborative text of [document].
///
/// Opens the handler the first time, then returns the same one. Positions
/// count runes, so an emoji is one character.
CRDTFugueTextHandler textOf(CRDTDocument document) {
  return document.handler(CRDTFugueTextHandler.spec, textHandlerId);
}

/// Opens the handlers of [document].
///
/// Client and server both call it, so they agree on what the document holds.
/// Calling it again on the same document is safe.
void openHandlers(CRDTDocument document) {
  textOf(document);
}
