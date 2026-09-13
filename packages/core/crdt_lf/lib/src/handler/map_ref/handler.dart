import 'package:crdt_lf/crdt_lf.dart';

/// # CRDT Map of references
///
/// A keyed container that stores [HandlerRef]s to other handlers instead of
/// raw values, enabling **nested CRDTs** while keeping the document storage
/// flat. Conflict resolution is the same last-writer-wins (by HLC) of
/// [CRDTMapHandler]; here the value of each key is a reference.
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
      : super(
          // The parent asks for a tag; the kind this class really is comes from
          // the [spec] override below, which the document reads.
          handlerType: _handlerType,
          valueCodec: const HandlerRefCodec(),
        );

  /// What this build reads for this handler type.
  ///
  /// A copy of what the handler this one extends reads, because that one's
  /// constant is private to its own file. The two agreeing is pinned by the
  /// table in `test/capabilities/capabilities_test.dart`, which compares every
  /// declaration against the decoders that actually dispatch.
  static const HandlerFormats _formats = HandlerFormats(
    operationKinds: {
      OperationType.kindInsert,
      OperationType.kindDelete,
      OperationType.kindUpdate,
    },
    blobVersions: BlobVersionRange.single(1),
  );

  /// The tag this kind travels under; see [Handler.handlerType].
  ///
  /// Fixed here because this handler is not generic: there is no type argument
  /// to carry, so there is nothing for a caller to choose.
  static const String _handlerType = 'CRDTMapRefHandler';

  /// {@macro builtin_handler_spec}
  static final HandlerSpec<CRDTMapRefHandler> _spec = HandlerSpec(
    _handlerType,
    CRDTMapRefHandler.new,
    formats: _formats,
  );

  @override
  HandlerSpec<CRDTMapRefHandler> get spec => _spec;

  /// Associates [key] with a reference to [handler].
  ///
  /// {@macro handlers_in_ref}
  void setRef(String key, Handler<dynamic> handler) {
    set(key, HandlerRef.of(handler));
  }

  /// The child at [key], made by [build] when [key] holds nothing yet.
  ///
  /// Safe to call again: the second call resolves the reference the first one
  /// wrote and hands back that handler. Pass a constructor tear-off —
  /// `todo.child('done', CRDTFugueTextHandler.new)`.
  ///
  /// Throws [HandlerAlreadyRegisteredException] when [key] already holds a
  /// child of another kind. A reference carries the kind, so that holds even
  /// for a child this peer has never opened. That is the usual shape for a tree
  /// that arrived from a peer.
  ///
  /// Learning the kind of an undeclared child means building it first. So in
  /// that one case the handler stays on the document, the way
  /// [HandlerSpec.create] leaves one whose checks failed.
  T child<T extends Handler<dynamic>>(String key, HandlerBuilder<T> build) {
    final ref = value[key];
    if (ref != null) {
      // A kind this document knows: resolving it checks the tag for free.
      final resolved = doc.resolveHandler(ref);
      if (resolved != null) {
        if (resolved is T) {
          return resolved;
        }
        throw HandlerAlreadyRegisteredException(
          'Key $key holds a ${ref.type}, which is not a $T',
        );
      }

      // A kind nothing here declared. `build` is the only thing that can say
      // what kind it makes, and it only says it by making one — so the check
      // comes after.
      final built = build(doc, ref.id);
      if (built.handlerType != ref.type) {
        throw HandlerAlreadyRegisteredException(
          'Key $key holds a ${ref.type}, not a ${built.handlerType}',
        );
      }
      return built;
    }

    final created = build(doc, doc.newHandlerId());
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

  @override
  Iterable<HandlerRef> childRefs() => value.values;

  @override
  Object? toNested(Set<String> visiting) {
    final out = <String, Object?>{};
    for (final entry in value.entries) {
      final ref = entry.value;
      if (visiting.contains(ref.id)) {
        out[entry.key] = null;
        continue;
      }
      final child = doc.resolveHandler(ref);
      out[entry.key] =
          child == null ? null : nestedValueOf(child, {...visiting, ref.id});
    }
    return out;
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
