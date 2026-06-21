import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter_example/shared/example_document.dart';

const _kDocumentId = 'document';

/// Document controller for the nested "document" example.
///
/// The whole document is a tree of nested CRDT containers stored flat in the
/// [CRDTDocument] registry and linked by references:
///
/// ```
/// document            CRDTMovableListRefHandler   (sortable chapters)
///   └ chapter         CRDTMapRefHandler
///       ├ title       CRDTFugueTextHandler        (collaborative text)
///       └ paragraphs  CRDTMovableListRefHandler   (sortable paragraphs)
///           └ paragraph  CRDTMapRefHandler
///               ├ text     CRDTFugueTextHandler    (collaborative text)
///               └ items    CRDTMovableListRefHandler (sortable list)
///                   └ item   CRDTFugueTextHandler
/// ```
///
/// Every node is a standard CRDT, so concurrent edits merge conflict-free and
/// the whole tree converges across peers. The root handler is a movable list
/// of chapter references; children are resolved lazily through the document
/// registry (and reconstructed on a remote peer from the received changes).
class DocumentState extends ExampleDocument<CRDTMovableListRefHandler> {
  /// Creates a document controller for [author] wired to [network].
  DocumentState({required super.author, required super.network});

  @override
  CRDTMovableListRefHandler createHandler(BaseCRDTDocument doc) {
    // Register the factories so children received from a remote peer (or a
    // time-travel session) can be reconstructed by type.
    doc.registerDefaultFactories();
    return CRDTMovableListRefHandler(doc, _kDocumentId);
  }

  // --- Reads (from the current view: live document or time-travel) ---

  /// The chapters of the document in order.
  List<CRDTMapRefHandler> get chapters => _resolveMapList(handler);

  /// The title text handler of [chapter], or `null` if not set yet.
  CRDTFugueTextHandler? chapterTitle(CRDTMapRefHandler chapter) =>
      chapter.getRef('title') as CRDTFugueTextHandler?;

  /// The paragraphs of [chapter] in order.
  List<CRDTMapRefHandler> paragraphsOf(CRDTMapRefHandler chapter) {
    final list = chapter.getRef('paragraphs') as CRDTMovableListRefHandler?;
    return list == null ? const [] : _resolveMapList(list);
  }

  /// The body text handler of [paragraph], or `null` if not set yet.
  CRDTFugueTextHandler? paragraphText(CRDTMapRefHandler paragraph) =>
      paragraph.getRef('text') as CRDTFugueTextHandler?;

  /// The sortable item text handlers of [paragraph] in order.
  List<CRDTFugueTextHandler> itemsOf(CRDTMapRefHandler paragraph) {
    final list = paragraph.getRef('items') as CRDTMovableListRefHandler?;
    if (list == null) {
      return const [];
    }
    return [
      for (var i = 0; i < list.value.length; i++)
        if (list.getRefAt(i) case final CRDTFugueTextHandler item) item,
    ];
  }

  List<CRDTMapRefHandler> _resolveMapList(CRDTMovableListRefHandler list) {
    return [
      for (var i = 0; i < list.value.length; i++)
        if (list.getRefAt(i) case final CRDTMapRefHandler node) node,
    ];
  }

  // --- Writes (always target the live document) ---

  /// Appends a new chapter with the given [title].
  void addChapter(String title) {
    final titleHandler = _newText(title);
    final paragraphs = CRDTMovableListRefHandler(document, _newId());
    final chapter =
        CRDTMapRefHandler(document, _newId())
          ..setRef('title', titleHandler)
          ..setRef('paragraphs', paragraphs);
    liveHandler.insertRef(liveHandler.value.length, chapter);
  }

  /// Moves a chapter from [from] to [to].
  void reorderChapters(int from, int to) => liveHandler.move(from, to);

  /// Removes the chapter at [index].
  void removeChapter(int index) => liveHandler.delete(index);

  /// Appends a new paragraph (with [text]) to [paragraphs].
  void addParagraph(CRDTMovableListRefHandler paragraphs, String text) {
    final textHandler = _newText(text);
    final items = CRDTMovableListRefHandler(document, _newId());
    final paragraph =
        CRDTMapRefHandler(document, _newId())
          ..setRef('text', textHandler)
          ..setRef('items', items);
    paragraphs.insertRef(paragraphs.value.length, paragraph);
  }

  /// Moves a paragraph inside [paragraphs] from [from] to [to].
  void reorderParagraphs(
    CRDTMovableListRefHandler paragraphs,
    int from,
    int to,
  ) {
    paragraphs.move(from, to);
  }

  /// Removes the paragraph at [index] from [paragraphs].
  void removeParagraph(CRDTMovableListRefHandler paragraphs, int index) {
    paragraphs.delete(index);
  }

  /// Appends a new sortable item (with [text]) to [items].
  void addItem(CRDTMovableListRefHandler items, String text) {
    items.insertRef(items.value.length, _newText(text));
  }

  /// Moves an item inside [items] from [from] to [to].
  void reorderItems(CRDTMovableListRefHandler items, int from, int to) {
    items.move(from, to);
  }

  /// Removes the item at [index] from [items].
  void removeItem(CRDTMovableListRefHandler items, int index) {
    items.delete(index);
  }

  /// Replaces the whole content of [text] with [value] (collaborative edit).
  void editText(CRDTFugueTextHandler text, String value) {
    text.change(value);
  }

  /// The paragraphs list handler of [chapter] on the live document, or `null`.
  CRDTMovableListRefHandler? liveParagraphsOf(CRDTMapRefHandler chapter) =>
      chapter.getRef('paragraphs') as CRDTMovableListRefHandler?;

  /// The items list handler of [paragraph] on the live document, or `null`.
  CRDTMovableListRefHandler? liveItemsOf(CRDTMapRefHandler paragraph) =>
      paragraph.getRef('items') as CRDTMovableListRefHandler?;

  String _newId() => document.newHandlerId();

  CRDTFugueTextHandler _newText(String value) {
    final handler = CRDTFugueTextHandler(document, _newId());
    if (value.isNotEmpty) {
      handler.insert(0, value);
    }
    return handler;
  }
}
