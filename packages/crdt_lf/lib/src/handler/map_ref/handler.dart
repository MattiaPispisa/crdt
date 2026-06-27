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
/// final doc = CRDTDocument()..registerDefaultFactories();
/// final root = CRDTMapRefHandler(doc, 'root');
/// final title = CRDTFugueTextHandler(doc, doc.newHandlerId());
/// root.setRef('title', title);
/// title.insert(0, 'Hello');
/// print(root.resolved); // {title: 'Hello'}
/// ```
class CRDTMapRefHandler extends CRDTMapHandler<HandlerRef>
    implements ContainerHandler {
  /// Creates a map-of-references handler bound to [doc] with the given [id].
  CRDTMapRefHandler(super.doc, super.id)
      : super(valueCodec: const HandlerRefCodec());

  /// Stable type tag (minification-safe). See [Handler.handlerType].
  @override
  String get handlerType => kMapRefHandlerType;

  /// Associates [key] with a reference to [handler].
  ///
  /// {@macro handlers_in_ref}
  void setRef(String key, Handler<dynamic> handler) {
    set(key, HandlerRef.of(handler));
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
