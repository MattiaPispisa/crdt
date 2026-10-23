import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/handler/fugue/fugue_snapshot.dart';

/// # CRDT ordered list of references
///
/// An ordered container that stores [HandlerRef]s to other handlers instead of
/// raw values, enabling **nested CRDTs** while keeping the document storage
/// flat; each element is a reference to a child handler.
///
/// {@macro crdt_fugue_list_handler_algorithm}
///
/// The inherited [value] getter returns the raw `List<HandlerRef>`, a dead
/// ref (its target deleted) included; [resolved] keeps that same raw
/// position.
///
/// {@macro ref_live_index}
///
/// ## Example
/// ```dart
/// final doc = CRDTDocument();
/// final chapters = CRDTListRefHandler(doc, 'chapters');
/// final intro = CRDTFugueTextHandler(doc, doc.newHandlerId());
/// chapters.insertRef(0, intro);
/// intro.insert(0, 'Once upon a time');
/// print(chapters.resolved); // ['Once upon a time']
/// ```
base class CRDTListRefHandler extends CRDTFugueListHandler<HandlerRef>
    implements ContainerHandler {
  /// Creates an ordered list-of-references handler bound to [doc] with [id].
  CRDTListRefHandler(super.doc, super.id)
      : super.fromSpec(
          // Its own kind, not one the parent makes from a tag: a spec the
          // parent minted would build the parent's class, and a peer rebuilding
          // this ref would get a handler that is not a container.
          spec: spec,
          valueCodec: const HandlerRefCodec(),
        );

  /// Inserts a reference to [handler] at live position [index].
  ///
  /// {@template ref_live_index}
  /// Indexes count only the live refs (one whose target is deleted is
  /// skipped), the same way a Fugue list already counts only its visible
  /// positions. `index` at or past the live count appends.
  /// {@endtemplate}
  ///
  /// {@template handlers_in_ref}
  /// Only a reference (`id` + type) to [handler] is stored, not the handler
  /// itself, so [handler] must live on the **same** document. A [Handler]
  /// auto-registers on its document when constructed, so just create it with
  /// the same `doc` (e.g. `CRDTFugueTextHandler(doc, doc.newHandlerId())`); a
  /// handler from another document would neither resolve nor sync.
  /// {@endtemplate}
  void insertRef(int index, Handler<dynamic> handler) {
    insert(rawIndexOfLive(doc, value, index), HandlerRef.of(handler));
  }

  /// Returns the handler referenced at live [index], or `null` if out of
  /// range.
  ///
  /// {@macro ref_live_index}
  ///
  /// {@template ref_get_resolution}
  /// The handler is resolved — and built if needed — through the document; it
  /// is `null` when the document knows no kind under the reference's type.
  /// {@endtemplate}
  Handler<dynamic>? getRefAt(int index) {
    final live = liveRefs(doc, value);
    if (index < 0 || index >= live.length) {
      return null;
    }
    return doc.resolveHandler(live[index]);
  }

  /// The referenced handlers, in order.
  ///
  /// {@macro ref_get_resolution}
  ///
  /// A reference that resolves to `null` is left out.
  Iterable<Handler<dynamic>> get children => resolvedChildrenOf(doc, this);

  /// What this build reads for this handler type.
  static const HandlerFormats _formats = HandlerFormats(
    operationKinds: {
      OperationType.kindInsert,
      OperationType.kindDelete,
      OperationType.kindUpdate,
    },
    blobVersions: BlobVersionRange.single(FugueSnapshot.version),
  );

  /// The tag this kind travels under; see [Handler.handlerType].
  static const String _handlerType = 'CRDTListRefHandler';

  /// {@macro builtin_handler_spec}
  static const HandlerSpec<CRDTListRefHandler> spec = HandlerSpec(
    _handlerType,
    CRDTListRefHandler.new,
    formats: _formats,
  );

  /// Inserts a child of the kind [spec] names at live [index], and returns
  /// it.
  ///
  /// {@macro ref_live_index}
  ///
  /// Always a new child; use [getRefAtAs] to read one back.
  ///
  /// ```dart
  /// final block = blocks.insertChild(0, CRDTFugueTextHandler.spec);
  /// ```
  T insertChild<T extends Handler<dynamic>>(int index, HandlerSpec<T> spec) {
    final created = spec.create(doc, doc.newHandlerId());
    insertRef(index, created);
    return created;
  }

  /// Like [getRefAt] but returns the handler only when it is a [T], otherwise
  /// `null` — removing the need for an `as` cast at the call site.
  ///
  /// {@macro handler_ref_typed}
  T? getRefAtAs<T extends Handler<dynamic>>(int index) =>
      typedRef<T>(getRefAt(index));

  /// Removes the element at live [index] and deletes the child it
  /// references, in one transaction.
  ///
  /// {@macro ref_live_index}
  ///
  /// {@template remove_child}
  /// The child is deleted with [BaseCRDTDocument.deleteHandlerRef], subtree
  /// included, for every peer, also when this peer cannot build it. An undo
  /// puts the reference back, and it resolves to nothing: a delete is final.
  /// {@endtemplate}
  ///
  /// Throws a [RangeError] when [index] is out of range.
  void removeChildAt(int index) {
    final refs = value;
    final live = liveRefs(doc, refs);
    if (index < 0 || index >= live.length) {
      throw RangeError.index(index, live, 'index');
    }
    final raw = rawIndexOfLive(doc, refs, index);
    doc.runInTransaction(() {
      delete(raw, 1);
      doc.deleteHandlerRef(refs[raw]);
    });
  }

  @override
  Iterable<HandlerRef> childRefs() => liveRefs(doc, value);

  @override
  Object? toNested(Set<String> visiting) {
    return [
      for (final ref in value) resolveNestedRef(doc, ref, visiting),
    ];
  }

  /// The fully resolved subtree rooted at this list, as a `List<Object?>`.
  ///
  /// {@template ref_resolved}
  /// Each reference is replaced by the resolved value of the child handler,
  /// recursively; a leaf handler resolves to its `value`. A reference that
  /// closes a cycle resolves to `null`. A reference to a deleted handler
  /// resolves to `null` in a list, which keeps its positions, and is left out
  /// of a map or a set.
  /// {@endtemplate}
  List<Object?> get resolved {
    final result = toNested(<String>{});
    return result is List<Object?> ? result : const [];
  }

  @override
  String toString() => 'CRDTListRefHandler($id, $value)';
}
