import 'package:crdt_lf/crdt_lf.dart';

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

  /// Inserts a reference to [handler] at position [index].
  ///
  /// [handler] must already be registered on the same document.
  void insertRef(int index, Handler<dynamic> handler) {
    insert(index, HandlerRef.of(handler));
  }

  /// Returns the handler referenced at [index], resolving (and lazily
  /// instantiating) it through the document, or `null` if out of range or
  /// unresolvable.
  Handler<dynamic>? getRefAt(int index) {
    final refs = value;
    if (index < 0 || index >= refs.length) {
      return null;
    }
    return doc.resolveHandler(refs[index]);
  }

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

  /// The fully resolved subtree rooted at this list.
  List<Object?> get resolved {
    final result = toNested(<String>{});
    return result is List<Object?> ? result : const [];
  }

  @override
  String toString() => 'CRDTListRefHandler($id, $value)';
}
