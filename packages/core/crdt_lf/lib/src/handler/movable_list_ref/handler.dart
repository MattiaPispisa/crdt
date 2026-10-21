import 'package:crdt_lf/crdt_lf.dart';

/// # CRDT movable ordered list of references
///
/// An ordered container of [HandlerRef]s that also supports an explicit
/// [move] operation preserving element identity across concurrent reorderings
/// (reusing [CRDTFugueMovableListHandler]). Ideal for things like reordering
/// slides or changing z-index while elements keep their identity.
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
/// final slides = CRDTMovableListRefHandler(doc, 'slides');
/// final a = CRDTMapRefHandler(doc, doc.newHandlerId());
/// final b = CRDTMapRefHandler(doc, doc.newHandlerId());
/// slides..insertRef(0, a)..insertRef(1, b)..move(1, 0);
/// ```
base class CRDTMovableListRefHandler
    extends CRDTFugueMovableListHandler<HandlerRef>
    implements ContainerHandler {
  /// Creates a movable list-of-references handler bound to [doc] with [id].
  CRDTMovableListRefHandler(super.doc, super.id)
      : super.fromSpec(
          // Its own kind, not one the parent makes from a tag: a spec the
          // parent minted would build the parent's class, and a peer rebuilding
          // this ref would get a handler that is not a container.
          spec: spec,
          valueCodec: const HandlerRefCodec(),
        );

  /// Inserts a reference to [handler] at live position [index].
  ///
  /// {@macro ref_live_index}
  ///
  /// {@macro handlers_in_ref}
  void insertRef(int index, Handler<dynamic> handler) {
    insert(rawIndexOfLive(doc, value, index), HandlerRef.of(handler));
  }

  /// Returns the handler referenced at live [index], or `null` if out of
  /// range.
  ///
  /// {@macro ref_live_index}
  ///
  /// {@macro ref_get_resolution}
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

  /// Moves the element currently at live position [from] so that, after the
  /// move, it appears at live position [to].
  ///
  /// {@macro ref_live_index}
  ///
  /// Negative `from`, `from` out of range or `from == to` is a no-op.
  @override
  void move(int from, int to) {
    if (from == to) {
      return;
    }
    final refs = value;
    final live = liveRefs(doc, refs);
    if (from < 0 || from >= live.length) {
      return;
    }
    super.move(
      rawIndexOfLive(doc, refs, from),
      rawIndexOfLive(doc, refs, to),
    );
  }

  /// What this build reads for this handler type.
  static const HandlerFormats _formats = HandlerFormats(
    operationKinds: {
      OperationType.kindInsert,
      OperationType.kindMove,
      OperationType.kindUpdate,
      OperationType.kindDelete,
    },
    blobVersions: BlobVersionRange.single(1),
  );

  /// The tag this kind travels under; see [Handler.handlerType].
  static const String _handlerType = 'CRDTMovableListRefHandler';

  /// {@macro builtin_handler_spec}
  static const HandlerSpec<CRDTMovableListRefHandler> spec = HandlerSpec(
    _handlerType,
    CRDTMovableListRefHandler.new,
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
  /// {@macro remove_child}
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
      delete(raw);
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
  /// {@macro ref_resolved}
  List<Object?> get resolved {
    final result = toNested(<String>{});
    return result is List<Object?> ? result : const [];
  }

  @override
  String toString() => 'CRDTMovableListRefHandler($id, $value)';
}
