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
/// final doc = CRDTDocument()..registerDefaultFactories();
/// final slides = CRDTMovableListRefHandler(doc, 'slides');
/// final a = CRDTMapRefHandler(doc, doc.newHandlerId());
/// final b = CRDTMapRefHandler(doc, doc.newHandlerId());
/// slides..insertRef(0, a)..insertRef(1, b)..move(1, 0);
/// ```
class CRDTMovableListRefHandler extends CRDTFugueMovableListHandler<HandlerRef>
    implements ContainerHandler {
  /// Creates a movable list-of-references handler bound to [doc] with [id].
  CRDTMovableListRefHandler(super.doc, super.id)
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
  String toString() => 'CRDTMovableListRefHandler($id, $value)';
}
