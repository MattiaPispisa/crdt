import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/handler/fugue/fugue_snapshot.dart';

/// # CRDT ordered list of references
///
/// An ordered container that stores [HandlerRef]s to other handlers instead of
/// raw values, enabling **nested CRDTs** while keeping the document storage
/// flat. It reuses the Fugue algorithm of [CRDTFugueListHandler] (so concurrent
/// insertions in the same region do not interleave); each element is a
/// reference to a child handler.
///
/// The inherited [value] getter returns the raw `List<HandlerRef>`; [resolved]
/// returns the fully resolved subtree (`List<Object?>`).
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

  /// Inserts a reference to [handler] at position [index].
  ///
  /// {@template handlers_in_ref}
  /// Only a reference (`id` + type) to [handler] is stored, not the handler
  /// itself, so [handler] must live on the **same** document. A [Handler]
  /// auto-registers on its document when constructed, so just create it with
  /// the same `doc` (e.g. `CRDTFugueTextHandler(doc, doc.newHandlerId())`); a
  /// handler from another document would neither resolve nor sync.
  /// {@endtemplate}
  void insertRef(int index, Handler<dynamic> handler) {
    insert(index, HandlerRef.of(handler));
  }

  /// Returns the handler referenced at [index], or `null` if out of range.
  ///
  /// {@template ref_get_resolution}
  /// The handler is resolved — and built if needed — through the document; it
  /// is `null` when the document knows no kind under the reference's type.
  /// {@endtemplate}
  Handler<dynamic>? getRefAt(int index) {
    final refs = value;
    if (index < 0 || index >= refs.length) {
      return null;
    }
    return doc.resolveHandler(refs[index]);
  }

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
  /// {@template ref_resolved}
  /// Each reference is replaced by the resolved value of the child handler,
  /// recursively; a leaf handler resolves to its `value`. A reference that
  /// closes a cycle resolves to `null`.
  /// {@endtemplate}
  List<Object?> get resolved {
    final result = toNested(<String>{});
    return result is List<Object?> ? result : const [];
  }

  @override
  String toString() => 'CRDTListRefHandler($id, $value)';
}
