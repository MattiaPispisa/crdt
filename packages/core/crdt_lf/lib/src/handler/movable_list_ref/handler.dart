import 'package:crdt_lf/crdt_lf.dart';

/// # CRDT movable ordered list of references
///
/// An ordered container of [HandlerRef]s that also supports an explicit
/// [move] operation preserving element identity across concurrent reorderings
/// (reusing [CRDTFugueMovableListHandler]). Ideal for things like reordering
/// slides or changing z-index while elements keep their identity.
///
/// The inherited [value] getter returns the raw `List<HandlerRef>`; [resolved]
/// returns the fully resolved subtree (`List<Object?>`).
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

  /// Inserts a reference to [handler] at position [index].
  ///
  /// {@macro handlers_in_ref}
  void insertRef(int index, Handler<dynamic> handler) {
    insert(index, HandlerRef.of(handler));
  }

  /// Returns the handler referenced at [index], or `null` if out of range.
  ///
  /// {@macro ref_get_resolution}
  Handler<dynamic>? getRefAt(int index) {
    final refs = value;
    if (index < 0 || index >= refs.length) {
      return null;
    }
    return doc.resolveHandler(refs[index]);
  }

  /// What this build reads for this handler type.
  ///
  /// A copy of what the handler this one extends reads, because that one's
  /// constant is private to its own file. The two agreeing is pinned by the
  /// table in `test/capabilities/capabilities_test.dart`, which compares every
  /// declaration against the decoders that actually dispatch.
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

  /// Inserts a child of the kind [spec] names at [index], and returns it.
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

  @override
  Iterable<HandlerRef> childRefs() => value;

  @override
  Object? toNested(Set<String> visiting) {
    final out = <Object?>[];
    for (final ref in value) {
      if (visiting.contains(ref.id)) {
        out.add(null);
        continue;
      }
      final child = doc.resolveHandler(ref);
      out.add(
        child == null ? null : nestedValueOf(child, {...visiting, ref.id}),
      );
    }
    return out;
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
