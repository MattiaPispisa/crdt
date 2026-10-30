// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:convert';
import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';

/// A serializable reference to another [Handler].
///
/// Container handlers (see [ContainerHandler]) store [HandlerRef]s instead of
/// raw data, keeping the document storage **flat**: every handler lives in the
/// document registry keyed by its [id], and a parent points to a child by id.
///
/// The [type] is the child handler's [Handler.handlerType], which is the key
/// used to look up a [HandlerSpec] when reconstructing the tree on a remote
/// peer.
class HandlerRef {
  /// Creates a reference to the handler with the given [id] and [type].
  const HandlerRef(this.id, this.type);

  /// Builds a reference pointing at [handler].
  factory HandlerRef.of(Handler<dynamic> handler) =>
      HandlerRef(handler.id, handler.handlerType);

  /// The referenced handler's unique id.
  final String id;

  /// The kind of the referenced handler; see [Handler.handlerType].
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
    UVarint.writeString(value.type, out);
    out.add(utf8.encode(value.id));
    return out.toBytes();
  }

  @override
  HandlerRef decode(Uint8List bytes) {
    final typeRecord = UVarint.readString(
      bytes,
      offset: 0,
      what: 'HandlerRef type',
    );
    final id = utf8.decode(
      Uint8List.sublistView(bytes, typeRecord.nextOffset),
    );
    return HandlerRef(id, typeRecord.value);
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

  /// Resolves this handler's subtree, replacing each reference with the
  /// resolved value of the child handler (see [nestedValueOf]).
  ///
  /// [visiting] carries the set of handler ids already on the current
  /// resolution path; a reference whose id is already in [visiting] is a cycle
  /// and resolves to `null` instead of recursing forever.
  Object? toNested(Set<String> visiting);
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

/// Resolves [ref] to a nested value through [doc], with [nestedValueOf].
///
/// [visiting] is the set of handler ids on the current resolution path, as in
/// [ContainerHandler.toNested]. Returns `null` for a reference that closes a
/// cycle, or that [BaseCRDTDocument.resolveHandler] cannot resolve.
Object? resolveNestedRef(
  BaseCRDTDocument doc,
  HandlerRef ref,
  Set<String> visiting,
) {
  if (visiting.contains(ref.id)) {
    return null;
  }
  final child = doc.resolveHandler(ref);
  return child == null ? null : nestedValueOf(child, {...visiting, ref.id});
}

/// Resolves [handler] to a nested value: recurses through
/// [ContainerHandler]s and returns the [Handler.value] of any other handler
/// as is.
///
/// A leaf value keeps its own type: a `Set`, a custom `T`, an aggregate
/// state. The result is JSON-safe only when every leaf value is.
///
/// Container handlers are checked first, so a container that also extends a
/// leaf handler (e.g. [CRDTMapRefHandler] over [CRDTMapHandler]) resolves
/// through [ContainerHandler.toNested], not as a leaf. A handler that does
/// not override [Handler.value] resolves to `null`.
Object? nestedValueOf(Handler<dynamic> handler, Set<String> visiting) {
  if (handler is ContainerHandler) {
    return (handler as ContainerHandler).toNested(visiting);
  }
  return handler.value;
}

/// The subset of [refs] whose target is not deleted, in the same order.
List<HandlerRef> liveRefs(BaseCRDTDocument doc, Iterable<HandlerRef> refs) =>
    refs.where((ref) => !doc.isDeleted(ref.id)).toList(growable: false);

/// The position in [refs] of the [liveIndex]-th ref whose target is not
/// deleted.
///
/// `refs` keeps a deleted ref's slot (a CRDT list never compacts), so a
/// position among only the live refs ("live index") can differ from its raw
/// position in `refs`. A `liveIndex` at or past the live count maps to
/// `refs.length`, the append boundary; one at or below zero maps to `0`.
int rawIndexOfLive(
  BaseCRDTDocument doc,
  List<HandlerRef> refs,
  int liveIndex,
) {
  if (liveIndex <= 0) {
    return 0;
  }
  var seen = 0;
  for (var i = 0; i < refs.length; i++) {
    if (!doc.isDeleted(refs[i].id)) {
      if (seen == liveIndex) {
        return i;
      }
      seen++;
    }
  }
  return refs.length;
}

/// Resolves every live reference [handler] holds, in the order
/// [ContainerHandler.childRefs] gives them.
///
/// Backs every ref-container's `children` getter.
Iterable<Handler<dynamic>> resolvedChildrenOf(
  BaseCRDTDocument doc,
  ContainerHandler handler,
) =>
    handler.childRefs().map(doc.resolveHandler).whereType<Handler<dynamic>>();
