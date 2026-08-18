import 'package:crdt_lf/src/document/document.dart';
import 'package:crdt_lf/src/operation/id.dart';
import 'package:crdt_lf/src/operation/operation.dart';

const _insert = 'insert';
const _delete = 'delete';
const _update = 'update';
const _move = 'move';

/// The kind of change an operation applies, scoped to the handler that owns it.
///
/// Holds the binary kind written in the operation envelope (u8) together with
/// the handler type it belongs to. The kind alone never identifies an
/// operation: the envelope carries the handler type before it, so two handlers
/// may use the same byte for two unrelated semantics.
///
/// It also says whether operations of this kind carry an [OperationId]
/// (see [stamped]).
class OperationType {
  OperationType._({
    required this.handler,
    required this.type,
    required this.kind,
    required this.stamped,
  });

  /// Insert operation
  factory OperationType.insert(
    Handler<dynamic> handler, {
    bool stamped = false,
  }) {
    return OperationType._(
      handler: handler.handlerType,
      type: _insert,
      kind: kindInsert,
      stamped: stamped,
    );
  }

  /// Delete operation
  factory OperationType.delete(
    Handler<dynamic> handler, {
    bool stamped = false,
  }) {
    return OperationType._(
      handler: handler.handlerType,
      type: _delete,
      kind: kindDelete,
      stamped: stamped,
    );
  }

  /// Update operation
  factory OperationType.update(
    Handler<dynamic> handler, {
    bool stamped = false,
  }) {
    return OperationType._(
      handler: handler.handlerType,
      type: _update,
      kind: kindUpdate,
      stamped: stamped,
    );
  }

  /// Move operation — used by handlers that support reordering elements
  /// without changing their identity (e.g. `CRDTFugueMovableListHandler`).
  factory OperationType.move(
    Handler<dynamic> handler, {
    bool stamped = false,
  }) {
    return OperationType._(
      handler: handler.handlerType,
      type: _move,
      kind: kindMove,
      stamped: stamped,
    );
  }

  /// Declares an operation kind owned by [handler].
  ///
  /// [kind] is scoped to the handler type, so a handler that needs a fifth
  /// semantics declares its own instead of reusing one of the four
  /// conventional names. Values `0-3` are those four ([kindInsert],
  /// [kindDelete], [kindUpdate], [kindMove]) and are best left alone so that
  /// tooling can label them without knowing the handler; `4` to [maxKind] are
  /// free.
  ///
  /// [name] labels the kind in [toPayload] and in debug output. It carries no
  /// meaning on the wire — only [kind] is written there.
  ///
  /// Turn on [stamped] for a kind that resolves conflicts by
  /// last-writer-wins.
  ///
  /// The upper half of the byte is not available: bit 7 is reserved by the
  /// envelope, which uses it to signal that a stamp follows the kind.
  factory OperationType.custom(
    Handler<dynamic> handler, {
    required int kind,
    required String name,
    bool stamped = false,
  }) {
    if (kind < 0 || kind > maxKind) {
      throw ArgumentError.value(
        kind,
        'kind',
        'must be in 0..$maxKind, because bit 7 of the kind byte is reserved '
            'by the operation envelope',
      );
    }

    return OperationType._(
      handler: handler.handlerType,
      type: name,
      kind: kind,
      stamped: stamped,
    );
  }

  /// The highest value [kind] can take.
  ///
  /// Bit 7 belongs to the envelope, which is why the ceiling is 127 and not
  /// 255.
  static const int maxKind = 0x7F;

  /// Binary kind value for insert (u8 in the operation envelope).
  static const int kindInsert = 0;

  /// Binary kind value for delete (u8 in the operation envelope).
  static const int kindDelete = 1;

  /// Binary kind value for update (u8 in the operation envelope).
  static const int kindUpdate = 2;

  /// Binary kind value for move (u8 in the operation envelope).
  static const int kindMove = 3;

  /// The conventional name of [kind] for the four values every handler uses
  /// the same way, or `null` beyond them.
  ///
  /// Returns `null` past those four: the meaning of a higher kind depends on
  /// the handler type that precedes it in the envelope, so a total
  /// `kind -> name` function is not expressible.
  static String? wellKnownName(int kind) {
    if (kind == kindInsert) {
      return _insert;
    }
    if (kind == kindDelete) {
      return _delete;
    }
    if (kind == kindUpdate) {
      return _update;
    }
    if (kind == kindMove) {
      return _move;
    }
    return null;
  }

  /// Handler type
  final String handler;

  /// Operation type
  final String type;

  /// Binary kind value written in the operation envelope (u8).
  final int kind;

  /// Whether an operation of this kind is marked with an [OperationId].
  ///
  /// A stamp is a unique, totally ordered mark: unique because the document
  /// mints one id per operation, ordered because [OperationId] compares by
  /// clock first and by peer second. A handler reads it from
  /// [Operation.stamp], which is set before the operation reaches
  /// `incrementCachedState`.
  ///
  /// The stamp is the id of the change that carries the operation, so it
  /// costs no bytes of its own: bit 7 of the kind byte carries the
  /// declaration, and nothing follows it.
  ///
  /// The declaration is local, not part of the wire format. Two builds that
  /// disagree about a kind are refused on decode, in both directions: a
  /// missing stamp and an unexpected one are equally visible.
  final bool stamped;

  /// Compares two [OperationType]s for equality
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is OperationType &&
        other.handler == handler &&
        other.type == type &&
        other.kind == kind &&
        other.stamped == stamped;
  }

  late final int _hashCode = Object.hash(handler, type, kind, stamped);

  /// Returns a hash code for this [OperationType]
  @override
  int get hashCode => _hashCode;

  /// Returns a payload for this [OperationType]
  String toPayload() {
    return '$handler:$type';
  }
}
