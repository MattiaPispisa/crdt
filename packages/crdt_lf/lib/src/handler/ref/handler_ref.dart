import 'dart:convert';
import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/handler/handler_type.dart';

/// A factory that instantiates a [Handler] of a specific runtime type for a
/// given [BaseCRDTDocument] and handler id.
///
/// Registered on the document and used to rebuild nested handlers on a peer
/// that only received the [Change]s/[Snapshot], without prior knowledge of the
/// document structure.
typedef HandlerFactory = Handler<dynamic> Function(
  BaseCRDTDocument doc,
  String id,
);

/// A serializable reference to another [Handler].
///
/// Container handlers (see [ContainerHandler]) store [HandlerRef]s instead of
/// raw data, keeping the document storage **flat**: every handler lives in the
/// document registry keyed by its [id], and a parent points to a child by id.
///
/// The [type] is the child handler's [Handler.handlerType], which is the key
/// used to look up a [HandlerFactory] when reconstructing the tree on a remote
/// peer.
class HandlerRef {
  /// Creates a reference to the handler with the given [id] and [type].
  const HandlerRef(this.id, this.type);

  /// Builds a reference pointing at [handler].
  factory HandlerRef.of(Handler<dynamic> handler) =>
      HandlerRef(handler.id, handler.handlerType);

  /// The referenced handler's unique id.
  final String id;

  /// The referenced handler's type tag (factory key).
  ///
  /// See [Handler.handlerType].
  final String type;

  @override
  bool operator ==(Object other) =>
      other is HandlerRef && other.id == id && other.type == type;

  @override
  int get hashCode => Object.hash(id, type);

  @override
  String toString() => 'HandlerRef($type#$id)';
}

/// [ValueCodec] for [HandlerRef].
///
/// Binary layout: `[uvarint typeLen][utf8 type][utf8 id]` (the id occupies the
/// remaining bytes, so no length prefix is needed for it).
class HandlerRefCodec implements ValueCodec<HandlerRef> {
  /// Creates a const codec instance.
  const HandlerRefCodec();

  @override
  Uint8List encode(HandlerRef value) {
    final out = BytesBuilder(copy: false);
    final typeBytes = utf8.encode(value.type);
    UVarint.write(typeBytes.length, out);
    out
      ..add(typeBytes)
      ..add(utf8.encode(value.id));
    return out.toBytes();
  }

  @override
  HandlerRef decode(Uint8List bytes) {
    final typeLenRec = UVarint.read(bytes, offset: 0);
    final typeEnd = typeLenRec.nextOffset + typeLenRec.value;
    final type = utf8.decode(
      Uint8List.sublistView(bytes, typeLenRec.nextOffset, typeEnd),
    );
    final id = utf8.decode(Uint8List.sublistView(bytes, typeEnd));
    return HandlerRef(id, type);
  }
}

/// Marker interface implemented by handlers that store [HandlerRef]s pointing
/// at other handlers, forming a nested tree over the flat document registry.
///
/// Implementers expose the references they hold ([childRefs]) and a recursive
/// resolution of the whole subtree ([toNested]).
abstract class ContainerHandler {
  /// The direct references contained by this handler (used for tree
  /// materialization and root discovery).
  Iterable<HandlerRef> childRefs();

  /// Resolves this handler's subtree to plain Dart values, replacing each
  /// reference with the resolved value of the child handler.
  ///
  /// [visiting] carries the set of handler ids already on the current
  /// resolution path; a reference whose id is already in [visiting] is a cycle
  /// and resolves to `null` instead of recursing forever.
  Object? toNested(Set<String> visiting);
}

/// Convenience registration of the built-in factories needed to reconstruct
/// nested documents: the three container handlers plus the non-generic leaf
/// handlers ([CRDTTextHandler], [CRDTFugueTextHandler]).
///
/// Generic leaf handlers (e.g. `CRDTMapHandler<num>`) must be registered
/// explicitly with their concrete type string, since the type carried in a
/// [HandlerRef] includes the generic arguments.
extension RegisterDefaultFactories on BaseCRDTDocument {
  /// Registers the built-in container and non-generic leaf factories.
  void registerDefaultFactories() {
    registerFactory(kMapRefHandlerType, CRDTMapRefHandler.new);
    registerFactory(kListRefHandlerType, CRDTListRefHandler.new);
    registerFactory(kMovableListRefHandlerType, CRDTMovableListRefHandler.new);
    registerFactory(kTextHandlerType, CRDTTextHandler.new);
    registerFactory(kFugueTextHandlerType, CRDTFugueTextHandler.new);
  }
}

/// Casts an already-resolved [reference] to the handler type [T], returning
/// `null` when it is `null` or not a [T].
///
/// {@template handler_ref_typed}
/// [T] must be a concrete handler type.
/// An assertion ensures that `T` cannot be dynamic.
/// {@endtemplate}
T? typedRef<T extends Handler<dynamic>>(Handler<dynamic>? reference) {
  assert(
    T != Handler<dynamic>,
    'typedRef<T> requires a concrete handler type for T; '
    'use getRef/getRefAt when any handler is acceptable.',
  );
  return reference is T ? reference : null;
}

/// Resolves [handler] to a plain value: recurses through [ContainerHandler]s
/// and reads `value` from the built-in leaf handlers (text, list, map, ...).
///
/// Container handlers are checked first, so a container that also extends a
/// leaf handler (e.g. [CRDTMapRefHandler] over [CRDTMapHandler]) resolves
/// through [ContainerHandler.toNested], not as a leaf. Returns `null` for an
/// unrecognized handler type.
Object? nestedValueOf(Handler<dynamic> handler, Set<String> visiting) {
  if (handler is ContainerHandler) {
    return (handler as ContainerHandler).toNested(visiting);
  }
  if (handler is CRDTRegisterHandler<dynamic>) {
    return handler.value;
  }
  if (handler is CRDTTextHandler) {
    return handler.value;
  }
  if (handler is CRDTFugueTextHandler) {
    return handler.value;
  }
  if (handler is CRDTListHandler<dynamic>) {
    return handler.value;
  }
  if (handler is CRDTFugueListHandler<dynamic>) {
    return handler.value;
  }
  if (handler is CRDTFugueMovableListHandler<dynamic>) {
    return handler.value;
  }
  if (handler is CRDTMapHandler<dynamic>) {
    return handler.value;
  }
  if (handler is CRDTORSetHandler<dynamic>) {
    return handler.value;
  }
  if (handler is CRDTORMapHandler<dynamic, dynamic>) {
    return handler.value;
  }
  return null;
}
