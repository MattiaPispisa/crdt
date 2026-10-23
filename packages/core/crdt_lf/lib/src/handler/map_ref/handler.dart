import 'package:crdt_lf/crdt_lf.dart';

/// # CRDT Map of references
///
/// A keyed container that stores [HandlerRef]s to other handlers instead of
/// raw values, enabling **nested CRDTs** while keeping the document storage
/// flat; the value of each key is a reference.
///
/// {@macro crdt_map_handler_algorithm}
///
/// The inherited [value] getter returns the raw `Map<String, HandlerRef>`;
/// [resolved] returns the fully resolved subtree (`Map<String, Object?>`).
///
/// ## Example
/// ```dart
/// final doc = CRDTDocument();
/// final root = CRDTMapRefHandler(doc, 'root');
/// final title = CRDTFugueTextHandler(doc, doc.newHandlerId());
/// root.setRef('title', title);
/// title.insert(0, 'Hello');
/// print(root.resolved); // {title: 'Hello'}
/// ```
base class CRDTMapRefHandler extends CRDTMapHandler<HandlerRef>
    implements ContainerHandler {
  /// Creates a map-of-references handler bound to [doc] with the given [id].
  CRDTMapRefHandler(super.doc, super.id)
      : super.fromSpec(
          // Its own kind, not one the parent makes from a tag: a spec the
          // parent minted would build the parent's class, and a peer rebuilding
          // this ref would get a handler that is not a container.
          spec: spec,
          valueCodec: const HandlerRefCodec(),
        );

  /// What this build reads for this handler type.
  static const HandlerFormats _formats = HandlerFormats(
    operationKinds: {
      OperationType.kindInsert,
      OperationType.kindDelete,
      OperationType.kindUpdate,
    },
    blobVersions: BlobVersionRange.single(1),
  );

  /// The tag this kind travels under; see [Handler.handlerType].
  static const String _handlerType = 'CRDTMapRefHandler';

  /// {@macro builtin_handler_spec}
  static const HandlerSpec<CRDTMapRefHandler> spec = HandlerSpec(
    _handlerType,
    CRDTMapRefHandler.new,
    formats: _formats,
  );

  /// Associates [key] with a reference to [handler].
  ///
  /// {@macro handlers_in_ref}
  void setRef(String key, Handler<dynamic> handler) {
    set(key, HandlerRef.of(handler));
  }

  /// {@template ref_child}
  /// The child at [key], of the kind [spec] names, created when [key] holds
  /// nothing yet or a deleted child.
  ///
  /// Safe to call again: the second call hands back the child the first wrote.
  ///
  /// ```dart
  /// final title = chapter.child('title', CRDTFugueTextHandler.spec);
  /// ```
  ///
  /// Throws [HandlerAlreadyRegisteredException] when [key] holds a child of
  /// another kind, even one this peer has never opened.
  /// {@endtemplate}
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
    setRef(key, created);
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
  /// `null` — removing the need for an `as` cast at the call site.
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
    final ref = value[key];
    if (ref == null) {
      return;
    }
    doc.runInTransaction(() {
      delete(key);
      doc.deleteHandlerRef(ref);
    });
  }

  @override
  Iterable<HandlerRef> childRefs() => liveRefs(doc, value.values);

  /// The referenced handlers, in no particular order.
  ///
  /// {@macro ref_get_resolution}
  ///
  /// A reference that resolves to `null` is left out.
  Iterable<Handler<dynamic>> get children => resolvedChildrenOf(doc, this);

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
  String toString() => 'CRDTMapRefHandler($id, $value)';
}
