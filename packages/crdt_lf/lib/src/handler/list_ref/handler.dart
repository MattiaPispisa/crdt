import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/handler/handler_type.dart';

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
/// final doc = CRDTDocument()..registerDefaultFactories();
/// final chapters = CRDTListRefHandler(doc, 'chapters');
/// final intro = CRDTFugueTextHandler(doc, doc.newHandlerId());
/// chapters.insertRef(0, intro);
/// intro.insert(0, 'Once upon a time');
/// print(chapters.resolved); // ['Once upon a time']
/// ```
class CRDTListRefHandler extends CRDTFugueListHandler<HandlerRef>
    implements ContainerHandler {
  /// Creates an ordered list-of-references handler bound to [doc] with [id].
  CRDTListRefHandler(super.doc, super.id)
      : super(valueCodec: const HandlerRefCodec());

  /// Stable type tag (minification-safe). See [Handler.handlerType].
  @override
  String get handlerType => kListRefHandlerType;

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
  /// The handler is resolved — and lazily instantiated if needed — through the
  /// document registry; it is `null` when the reference's type has no
  /// registered factory.
  /// {@endtemplate}
  Handler<dynamic>? getRefAt(int index) {
    final refs = value;
    if (index < 0 || index >= refs.length) {
      return null;
    }
    return doc.resolveHandler(refs[index]);
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
