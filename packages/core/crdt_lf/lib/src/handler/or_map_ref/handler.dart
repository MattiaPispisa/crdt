import 'package:crdt_lf/crdt_lf.dart';

/// # CRDT OR-Map of references
///
/// A keyed container of [HandlerRef]s to other handlers, for **nested CRDTs**
/// over the flat document storage. Conflicts resolve as in [CRDTORMapHandler]:
/// a `put` concurrent with a `remove` of the same key wins, and two concurrent
/// `put`s keep the one with the higher stamp. [CRDTMapRefHandler] resolves
/// all three cases by last-writer-wins instead.
///
/// The inherited `value` getter returns the raw `Map<String, HandlerRef>`;
/// [resolved] returns the fully resolved subtree (`Map<String, Object?>`).
///
/// ## Example
/// ```dart
/// final doc = CRDTDocument();
/// final root = CRDTORMapRefHandler(doc, 'root');
/// root.child('title', CRDTFugueTextHandler.spec).insert(0, 'Hello');
/// print(root.resolved); // {title: Hello}
/// root.removeChild('title');
/// ```
base class CRDTORMapRefHandler extends CRDTORMapHandler<String, HandlerRef>
    implements ContainerHandler {
  /// Creates an OR-map-of-references handler bound to [doc] with [id].
  CRDTORMapRefHandler(super.doc, super.id)
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
    blobVersions: BlobVersionRange.single(1),
  );

  /// The tag this kind travels under; see [Handler.handlerType].
  static const String _handlerType = 'CRDTORMapRefHandler';

  /// {@macro builtin_handler_spec}
  static const HandlerSpec<CRDTORMapRefHandler> spec = HandlerSpec(
    _handlerType,
    CRDTORMapRefHandler.new,
    formats: _formats,
  );

  /// Associates [key] with a reference to [handler].
  ///
  /// {@macro handlers_in_ref}
  void putRef(String key, Handler<dynamic> handler) {
    put(key, HandlerRef.of(handler));
  }

  /// {@macro ref_child}
  T child<T extends Handler<dynamic>>(String key, HandlerSpec<T> spec) {
    final ref = value[key];
    if (ref != null && !doc.isDeleted(ref.id)) {
      if (ref.type != spec.type) {
        throw HandlerAlreadyRegisteredException(
          'Key $key holds a ${ref.type}, not a ${spec.type}',
        );
      }
      return doc.handler<T>(spec, ref.id);
    }

    final created = spec.create(doc, doc.newHandlerId());
    putRef(key, created);
    return created;
  }

  /// Returns the handler referenced by [key], or `null` if [key] is absent.
  ///
  /// {@macro ref_get_resolution}
  Handler<dynamic>? getRef(String key) {
    final ref = value[key];
    return ref == null ? null : doc.resolveHandler(ref);
  }

  /// Like [getRef] but returns the handler only when it is a [T], otherwise
  /// `null`.
  ///
  /// {@macro handler_ref_typed}
  T? getRefAs<T extends Handler<dynamic>>(String key) =>
      typedRef<T>(getRef(key));

  /// Removes [key] and deletes the child it references, in one transaction.
  ///
  /// {@macro remove_child}
  ///
  /// Does nothing when [key] is absent.
  void removeChild(String key) {
    final child = getRef(key);
    doc.runInTransaction(() {
      remove(key);
      if (child != null) {
        doc.deleteHandler(child);
      }
    });
  }

  @override
  Iterable<HandlerRef> childRefs() =>
      value.values.where((ref) => !doc.isDeleted(ref.id));

  @override
  Object? toNested(Set<String> visiting) {
    return {
      for (final entry in value.entries)
        if (!doc.isDeleted(entry.value.id))
          entry.key: resolveNestedRef(doc, entry.value, visiting),
    };
  }

  /// The fully resolved subtree, as a `Map<String, Object?>`.
  ///
  /// {@macro ref_resolved}
  Map<String, Object?> get resolved {
    final result = toNested(<String>{});
    return result is Map<String, Object?> ? result : const {};
  }

  @override
  String toString() => 'CRDTORMapRefHandler($id, $value)';
}
