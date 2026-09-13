import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/handler/handler_type.dart';

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
      : super(valueCodec: const HandlerRefCodec());

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

  /// {@macro builtin_handler_spec}
  static final HandlerSpec<CRDTMapRefHandler> spec = HandlerSpec.factory(
    kMapRefHandlerType,
    CRDTMapRefHandler.new,
    formats: _formats,
  );

  @override
  HandlerSpec<CRDTMapRefHandler> get handlerSpec => spec;

  /// Associates [key] with a reference to [handler].
  ///
  /// {@macro handlers_in_ref}
  void setRef(String key, Handler<dynamic> handler) {
    set(key, HandlerRef.of(handler));
  }

  /// The child at [key], created from [spec] when [key] holds nothing yet.
  ///
  /// Safe to call again: the second call resolves the reference the first one
  /// wrote and returns that handler, so the caller does not have to check
  /// first. Creating a handler by hand instead throws on an id already taken.
  ///
  /// ```dart
  /// final done = todo.child(doneKey, doneSpec)..set(true);
  /// ```
  ///
  /// Register [spec] on the document ([BaseCRDTDocument.register]) so a peer
  /// that receives the reference can rebuild the child from its tag.
  ///
  /// Throws [HandlerAlreadyRegisteredException] when [key] already holds a
  /// child of another kind.
  T child<T extends Handler<dynamic>>(String key, HandlerSpec<T> spec) {
    final existing = value[key];
    if (existing != null) {
      // The ref carries the type, so a key holding another kind is caught even
      // when that child was never opened here — which is the usual case for a
      // tree that arrived from a peer.
      if (existing.type != spec.type) {
        throw HandlerAlreadyRegisteredException(
          'Key $key holds a ${existing.type}, not a ${spec.type}',
        );
      }
      return doc.handler<T>(spec, existing.id);
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
