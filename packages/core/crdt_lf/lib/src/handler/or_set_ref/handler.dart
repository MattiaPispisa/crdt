import 'package:crdt_lf/crdt_lf.dart';

/// # CRDT OR-Set of references
///
/// An unordered container of [HandlerRef]s to other handlers, for **nested
/// CRDTs** over the flat document storage. Conflicts resolve as in
/// [CRDTORSetHandler]: an add concurrent with a remove of the same reference
/// wins.
///
/// The inherited `value` getter returns the raw `Set<HandlerRef>`; [children]
/// and [resolved] list the children sorted by handler id, so every peer reads
/// them in the same order.
///
/// ## Example
/// ```dart
/// final doc = CRDTDocument();
/// final notes = CRDTORSetRefHandler(doc, 'notes');
/// final note = notes.addChild(CRDTFugueTextHandler.spec)..insert(0, 'Hi');
/// print(notes.resolved); // [Hi]
/// notes.removeChild(note);
/// ```
base class CRDTORSetRefHandler extends CRDTORSetHandler<HandlerRef>
    implements ContainerHandler {
  /// Creates an OR-set-of-references handler bound to [doc] with [id].
  CRDTORSetRefHandler(super.doc, super.id)
      : super.fromSpec(
          // Its own kind, not one the parent makes from a tag: a peer
          // rebuilding this ref must get a container.
          spec: spec,
          valueCodec: const HandlerRefCodec(),
        );

  /// What this build reads for this handler type.
  static const HandlerFormats _formats = HandlerFormats(
    operationKinds: {
      OperationType.kindInsert,
      OperationType.kindDelete,
    },
    blobVersions: BlobVersionRange(1, 2),
  );

  /// The tag this kind travels under; see [Handler.handlerType].
  static const String _handlerType = 'CRDTORSetRefHandler';

  /// {@macro builtin_handler_spec}
  static const HandlerSpec<CRDTORSetRefHandler> spec = HandlerSpec(
    _handlerType,
    CRDTORSetRefHandler.new,
    formats: _formats,
  );

  /// Adds a reference to [handler].
  ///
  /// {@macro handlers_in_ref}
  void addRef(Handler<dynamic> handler) {
    add(HandlerRef.of(handler));
  }

  /// Adds a new child of the kind [spec] names, and returns it.
  ///
  /// Always a new child, as each call mints a new id.
  T addChild<T extends Handler<dynamic>>(HandlerSpec<T> spec) {
    final created = spec.create(doc, doc.newHandlerId());
    addRef(created);
    return created;
  }

  /// Removes the reference to [handler]; the handler itself stays.
  void removeRef(Handler<dynamic> handler) {
    remove(HandlerRef.of(handler));
  }

  /// Whether the set holds a reference to [handler].
  bool containsRef(Handler<dynamic> handler) =>
      contains(HandlerRef.of(handler));

  /// Removes the reference to [handler] and deletes it, in one transaction.
  ///
  /// {@macro remove_child}
  void removeChild(Handler<dynamic> handler) {
    doc.runInTransaction(() {
      removeRef(handler);
      doc.deleteHandler(handler);
    });
  }

  /// The referenced handlers, sorted by id.
  ///
  /// {@macro ref_get_resolution}
  ///
  /// A reference that resolves to `null` is left out.
  Iterable<Handler<dynamic>> get children => resolvedChildrenOf(doc, this);

  @override
  Iterable<HandlerRef> childRefs() => liveRefs(doc, _sortedRefs());

  /// [value] sorted by id; sorted again only after [value] changes.
  List<HandlerRef> _sortedRefs() {
    final refs = value;
    if (!identical(refs, _sortedFrom)) {
      _sorted = refs.toList()..sort((a, b) => a.id.compareTo(b.id));
      _sortedFrom = refs;
    }
    return _sorted;
  }

  Set<HandlerRef>? _sortedFrom;
  late List<HandlerRef> _sorted;

  @override
  Object? toNested(Set<String> visiting) {
    return [
      for (final ref in childRefs()) resolveNestedRef(doc, ref, visiting),
    ];
  }

  /// The fully resolved children, sorted by handler id.
  ///
  /// {@macro ref_resolved}
  List<Object?> get resolved {
    final result = toNested(<String>{});
    return result is List<Object?> ? result : const [];
  }

  @override
  String toString() => 'CRDTORSetRefHandler($id, $value)';
}
