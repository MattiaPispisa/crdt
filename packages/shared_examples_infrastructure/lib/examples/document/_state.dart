import 'package:crdt_lf/crdt_lf.dart';
import 'package:shared_examples_infrastructure/examples/ids.dart';
import 'package:shared_examples_infrastructure/shared/example_document.dart';

import '_blocks.dart';

/// Document controller for the nested "document" example.
///
/// The document keeps its Google-Docs-like outline — sortable chapters, each
/// with a title and sortable paragraphs — and each paragraph holds an
/// extensible, sortable list of **blocks**. Today a block is one of the kinds
/// in [documentBlockSpecs] (a [TextBlockSpec] or a [TodoBlockSpec]); new kinds
/// are added by registering another [BlockSpec], factory-style.
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
///               └ blocks   CRDTMovableListRefHandler (sortable, extensible)
///                   └ block   CRDTMapRefHandler     (single entry; key = kind)
///                         ├ 'text' → CRDTFugueTextHandler         (Text block)
///                         └ 'todo' → CRDTMovableListRefHandler    (Todo block)
///                               └ todo  CRDTMapRefHandler
///                                     ├ 'text' → CRDTFugueTextHandler  item text
///                                     └ 'done' → CRDTMapHandler<bool>  LWW flag
/// ```
///
/// Every node is a standard CRDT, so concurrent edits merge conflict-free and
/// the whole tree converges across peers. The root handler is a movable list
/// of chapter references; children are resolved lazily through the document
/// registry (and reconstructed on a remote peer from the received changes).
class DocumentExampleState extends ExampleDocument<CRDTMovableListRefHandler> {
  /// Creates a document controller over an already-synced [document].
  DocumentExampleState(super.document);

  static const _kTitleKey = 'title';
  static const _kParagraphsKey = 'paragraphs';
  static const _kTextKey = 'text';
  static const _kBlocksKey = 'blocks';
  static const _kDoneKey = 'done';

  // Stable type tag for the todo `done` register. Used both as the factory key
  // and as the handler's `handlerType`, so the two match even in a minified
  // (Flutter web `--release`) build where `runtimeType.toString()` would be an
  // opaque `"minified:..."` token. See [Handler.handlerType].
  static const _kDoneType = 'CRDTRegisterHandler<bool>';

  @override
  CRDTMovableListRefHandler createHandler(BaseCRDTDocument doc) {
    // Register the factories so children received from a remote peer (or a
    // time-travel session) can be reconstructed by type.
    doc.registerDefaultFactories();
    // The todo `done` flag is a nested CRDTRegisterHandler<bool> (a LWW
    // register), which is generic and therefore not part of the default
    // (non-generic) set, so register it explicitly — with the same stable tag
    // the handler is created with below.
    doc.registerFactory(
      _kDoneType,
      (d, id) => CRDTRegisterHandler<bool>(d, id, handlerType: _kDoneType),
    );
    return CRDTMovableListRefHandler(doc, ExampleHandlerIds.document);
  }

  /// The block specs available to add, used to build the "Add block" menu.
  List<BlockSpec> get blockSpecs => documentBlockSpecs;

  // --- Reads (from the current view: live document or time-travel) ---

  /// The chapters of the document in order.
  List<CRDTMapRefHandler> get chapters => _resolveMapList(handler);

  /// The title text handler of [chapter], or `null` if not set yet.
  CRDTFugueTextHandler? chapterTitle(CRDTMapRefHandler chapter) =>
      chapter.getRefAs<CRDTFugueTextHandler>(_kTitleKey);

  /// The paragraphs of [chapter] in order.
  List<CRDTMapRefHandler> paragraphsOf(CRDTMapRefHandler chapter) {
    final list = chapter.getRefAs<CRDTMovableListRefHandler>(_kParagraphsKey);
    return list == null ? const [] : _resolveMapList(list);
  }

  /// The body text handler of [paragraph], or `null` if not set yet.
  CRDTFugueTextHandler? paragraphText(CRDTMapRefHandler paragraph) =>
      paragraph.getRefAs<CRDTFugueTextHandler>(_kTextKey);

  /// The blocks of [paragraph] in order.
  List<CRDTMapRefHandler> blocksOf(CRDTMapRefHandler paragraph) {
    final list = paragraph.getRefAs<CRDTMovableListRefHandler>(_kBlocksKey);
    return list == null ? const [] : _resolveMapList(list);
  }

  /// The kind of [block] (the single key of the block map), or `null`.
  String? blockKind(CRDTMapRefHandler block) {
    final keys = block.value.keys;
    return keys.isEmpty ? null : keys.first;
  }

  /// The content handler of [block] (its single referenced child), or `null`.
  Handler<dynamic>? blockContent(CRDTMapRefHandler block) {
    final kind = blockKind(block);
    return kind == null ? null : block.getRef(kind);
  }

  /// The todo items of [todoList] in order.
  List<CRDTMapRefHandler> todosOf(CRDTMovableListRefHandler todoList) =>
      _resolveMapList(todoList);

  /// The text handler of a todo [item], or `null`.
  CRDTFugueTextHandler? todoText(CRDTMapRefHandler item) =>
      item.getRefAs<CRDTFugueTextHandler>(_kTextKey);

  /// Whether a todo [item] is marked done.
  bool todoDone(CRDTMapRefHandler item) {
    final done = item.getRefAs<CRDTRegisterHandler<bool>>(_kDoneKey);
    return done?.value ?? false;
  }

  List<CRDTMapRefHandler> _resolveMapList(CRDTMovableListRefHandler list) {
    return [
      for (var i = 0; i < list.value.length; i++)
        if (list.getRefAtAs<CRDTMapRefHandler>(i) case final node?) node,
    ];
  }

  // --- Writes (always target the live document) ---

  /// Appends a new chapter with the given [title].
  void addChapter(String title) {
    final chapter =
        CRDTMapRefHandler(document, _newId())
          ..setRef(_kTitleKey, _newText(title))
          ..setRef(_kParagraphsKey, newRefList());
    liveHandler.insertRef(liveHandler.value.length, chapter);
  }

  /// Moves a chapter from [from] to [to].
  void reorderChapters(int from, int to) => liveHandler.move(from, to);

  /// Removes the chapter at [index].
  void removeChapter(int index) => liveHandler.delete(index);

  /// Appends a new paragraph (with [text]) to [paragraphs].
  void addParagraph(CRDTMovableListRefHandler paragraphs, String text) {
    final paragraph =
        CRDTMapRefHandler(document, _newId())
          ..setRef(_kTextKey, _newText(text))
          ..setRef(_kBlocksKey, newRefList());
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

  /// Appends a new block of the given [spec] kind to [blocks].
  void addBlock(CRDTMovableListRefHandler blocks, BlockSpec spec) {
    final content = spec.createContent(this);
    final block = CRDTMapRefHandler(document, _newId())
      ..setRef(spec.kind, content);
    blocks.insertRef(blocks.value.length, block);
  }

  /// Moves a block inside [blocks] from [from] to [to].
  void reorderBlocks(CRDTMovableListRefHandler blocks, int from, int to) =>
      blocks.move(from, to);

  /// Removes the block at [index] from [blocks].
  void removeBlock(CRDTMovableListRefHandler blocks, int index) =>
      blocks.delete(index);

  /// Appends a new todo (with [text]) to [todoList].
  void addTodo(CRDTMovableListRefHandler todoList, String text) {
    final item =
        CRDTMapRefHandler(document, _newId())
          ..setRef(_kTextKey, _newText(text))
          ..setRef(_kDoneKey, _newDone(value: false));
    todoList.insertRef(todoList.value.length, item);
  }

  /// Toggles the done flag of a todo [item].
  void toggleTodo(CRDTMapRefHandler item) {
    final done = item.getRefAs<CRDTRegisterHandler<bool>>(_kDoneKey);
    if (done == null) {
      return;
    }
    done.set(!(done.value ?? false));
  }

  /// Replaces the text of a todo [item].
  void editTodoText(CRDTMapRefHandler item, String value) {
    item.getRefAs<CRDTFugueTextHandler>(_kTextKey)?.change(value);
  }

  /// Moves a todo inside [todoList] from [from] to [to].
  void reorderTodos(CRDTMovableListRefHandler todoList, int from, int to) =>
      todoList.move(from, to);

  /// Removes the todo at [index] from [todoList].
  void removeTodo(CRDTMovableListRefHandler todoList, int index) =>
      todoList.delete(index);

  /// Replaces the whole content of [text] with [value] (collaborative edit).
  void editText(CRDTFugueTextHandler text, String value) => text.change(value);

  // --- Live accessors for mutation (resolve handlers on the live document) ---

  /// The paragraphs list handler of [chapter] on the live document, or `null`.
  CRDTMovableListRefHandler? liveParagraphsOf(CRDTMapRefHandler chapter) =>
      chapter.getRefAs<CRDTMovableListRefHandler>(_kParagraphsKey);

  /// The blocks list handler of [paragraph] on the live document, or `null`.
  CRDTMovableListRefHandler? liveBlocksOf(CRDTMapRefHandler paragraph) =>
      paragraph.getRefAs<CRDTMovableListRefHandler>(_kBlocksKey);

  // --- Handler factories used by block specs ---

  /// Creates a new collaborative text handler (optionally seeded with [value]).
  CRDTFugueTextHandler newText([String value = '']) => _newText(value);

  /// Creates a new (empty) movable list-of-references handler.
  CRDTMovableListRefHandler newRefList() =>
      CRDTMovableListRefHandler(document, _newId());

  String _newId() => document.newHandlerId();

  CRDTFugueTextHandler _newText(String value) {
    final handler = CRDTFugueTextHandler(document, _newId());
    if (value.isNotEmpty) {
      handler.insert(0, value);
    }
    return handler;
  }

  CRDTRegisterHandler<bool> _newDone({required bool value}) {
    final handler = CRDTRegisterHandler<bool>(
      document,
      _newId(),
      handlerType: _kDoneType,
    );
    handler.set(value);
    return handler;
  }
}
