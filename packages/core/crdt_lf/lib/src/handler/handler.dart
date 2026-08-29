part of '../document/document.dart';

/// A per-kind decoder, keyed by [OperationEnvelope.kind].
///
/// A decoder is only handed the body: by the time one runs, the envelope has
/// already been confirmed to address this handler, and the body has already
/// been sliced out of the change's payload.
typedef OperationDecoders = Map<int, Operation Function(Uint8List body)>;

/// Abstract class for CRDT handlers
///
/// A handler is a component that manages the state of a specific
/// data structure in the CRDT system.
///
/// ## Extension points
///
/// Most of the members below this class are for **writing** a handler, not for
/// using one. Using a handler means calling the API of the concrete class
/// (`value`, `insert`, `set`, …); nothing here has to be called by hand.
///
/// A custom handler overrides:
///
/// - [id] and [operationDecoders] — required: how the handler is addressed
///   and how its operations are decoded.
/// - [getSnapshotState] — required: the state as bytes, seeded back through
///   [lastSnapshot].
/// - [handlerType] — for a handler that must survive dart2js minification.
/// - [incrementCachedState] — to advance the cached state by one operation
///   instead of replaying the history.
/// - [stateIsOrderIndependent] — only when the state is the same
///   whatever the order causally ready operations arrive in.
/// - [compound] — to collapse consecutive operations inside a transaction.
///
/// And it reads its state through [cachedState] / [updateCachedState],
/// replaying [operations] when there is nothing cached.
///
/// The four conventional operation kinds are ready to use as [insertType],
/// [deleteType], [updateType] and [moveType]. A handler that needs a fifth
/// semantics declares its own with [OperationType.custom] instead of reusing
/// one of those names:
///
/// ```dart
/// late final OperationType incrementType =
///     OperationType.custom(this, kind: 4, name: 'increment');
/// ```
///
/// The hooks the framework calls on a handler are private to this library, so
/// they never show up on a handler you hold.
abstract base class Handler<T>
    with DocumentConsumer, SnapshotProvider, CacheableStateProvider<T> {
  /// Creates a new handler for the given document.
  ///
  /// [handlerType] optionally overrides the type tag
  /// (see [Handler.handlerType]);
  /// pass a stable constant for generic handlers
  /// that must work in a minified build.
  Handler(this.doc, {String? handlerType}) : _handlerType = handlerType {
    doc.registerHandler(this);
  }

  /// The document that owns this handler
  final BaseCRDTDocument doc;

  final String? _handlerType;

  /// The decoders this handler owns, keyed by [OperationEnvelope.kind].
  ///
  /// A kind not in this map is refused with [UnknownOperationKindException]
  /// when a change carrying it is decoded.
  OperationDecoders get operationDecoders;

  /// Stable identifier of this handler's **type**.
  ///
  /// Used as the type tag in operation envelopes, in the snapshot handler
  /// manifest and in [HandlerRef]s, and as the key under which a
  /// [HandlerFactory] is registered (see [BaseCRDTDocument.registerFactory]).
  /// The same value is produced on every peer so changes route to the matching
  /// handler and nested handlers can be reconstructed remotely.
  ///
  /// Defaults to `runtimeType.toString()`, which is convenient but **not
  /// stable under dart2js minification**. Custom handlers
  /// that must work in a minified build (or persist/sync across builds) should
  /// override it with their own constant, or pass one to the constructor.
  String get handlerType => _handlerType ?? runtimeType.toString();

  /// Cached insert type instance for this handler, used in operations.
  ///
  /// Override it to declare the kind stamped, when concurrent inserts have to
  /// be resolved by last-writer-wins:
  ///
  /// ```dart
  /// @override
  /// late final OperationType insertType =
  ///     OperationType.insert(this, stamped: true);
  /// ```
  OperationType get insertType => _insertType ??= OperationType.insert(this);
  OperationType? _insertType;

  /// Cached delete type instance for this handler, used in operations.
  ///
  /// {@template stamped_kind_override}
  /// Override it to declare the kind stamped. See [OperationType.stamped].
  /// {@endtemplate}
  OperationType get deleteType => _deleteType ??= OperationType.delete(this);
  OperationType? _deleteType;

  /// Cached update type instance for this handler, used in operations.
  ///
  /// {@macro stamped_kind_override}
  OperationType get updateType => _updateType ??= OperationType.update(this);
  OperationType? _updateType;

  /// Cached move type instance for this handler, used in operations.
  ///
  /// {@macro stamped_kind_override}
  OperationType get moveType => _moveType ??= OperationType.move(this);
  OperationType? _moveType;

  /// During transaction consecutive operations can be compounded.
  ///
  /// By default, no compaction occurs and operations are returned as-is.
  ///
  /// Override this method to implement a compact algorithm.
  ///
  /// [accumulator] is the previous operation
  /// [current] is the current operation
  ///
  /// If [current] can be compounded with [accumulator],
  /// return the **new compounded** operation (union of the two).
  ///
  /// Otherwise, return `null`.
  ///
  /// The result may be [current] itself, but never [accumulator]: the fused
  /// operation carries the stamp of the later one, and the deltas waiting for
  /// the change it becomes are drained in stamp order. An earlier stamp leaves
  /// part of them behind. A fresh operation is stamped for you.
  Operation? compound(Operation accumulator, Operation current) => null;

  /// Looks up [envelope]'s kind in [operationDecoders] and returns what it
  /// decodes to.
  ///
  /// Throws [UnknownOperationKindException] on a kind this handler cannot
  /// decode.
  Operation _decodeOperation(OperationEnvelope envelope, Uint8List body) {
    final decode = operationDecoders[envelope.kind];
    if (decode == null) {
      throw UnknownOperationKindException(
        handlerType: envelope.handlerType,
        handlerId: envelope.handlerId,
        kind: envelope.kind,
      );
    }
    return decode(body);
  }

  /// Decodes the operation [change] carries, or `null` when the change is
  /// addressed to another handler.
  ///
  /// The single place the envelope is decoded: it checks the address, hands
  /// [_decodeOperation] a body it does not have to slice again, and gives the
  /// operation the id of the change that carried it.
  ///
  /// That id **is** the stamp, so it is the same value the writing peer
  /// folded into its own state.
  ///
  /// Throws a [FormatException] when the change disagrees with this build
  /// about [OperationType.stamped], in either direction: a kind this build
  /// stamps arriving undeclared, and one it does not stamp arriving declared.
  @override
  Operation? _operationFromChange(Change change) {
    final bytes = change.payloadBytes();
    final envelope = OperationEnvelopeCodec.decode(bytes);

    if (envelope.handlerId != id || envelope.handlerType != handlerType) {
      return null;
    }

    final body = Uint8List.sublistView(bytes, envelope.bodyOffset);
    final operation = _decodeOperation(envelope, body);

    if (operation.type.stamped && !envelope.stamped) {
      throw FormatException(
        'Operation ${operation.type.toPayload()} is not declared stamped by '
        'the peer that wrote it, but this kind resolves conflicts with a '
        'stamp here.',
      );
    }

    if (!operation.type.stamped && envelope.stamped) {
      throw FormatException(
        'Operation ${operation.type.toPayload()} is declared stamped by the '
        'peer that wrote it, but this build does not stamp that kind and '
        'would resolve it by another rule.',
      );
    }

    return operation..stamp = change.id;
  }

  /// Returns the [Operation]s required by this consumer to compute its state.
  ///
  /// The [Operation]s are returned in the order they were applied.
  List<Operation> operations() {
    final changes = doc
        .changesForHandler(
          id,
          fromVersionVector: _snapshotVersionVector(),
        )
        .sorted(inplace: true);

    // The list is sorted, so its last entry is the newest change the caller is
    // about to fold in. See [CacheableStateProvider._noteReplayBoundary].
    _noteReplayBoundary(changes.isEmpty ? null : changes.last);

    final operations = <Operation>[];
    for (final change in changes) {
      final operation = _operationFromChange(change);
      if (operation != null) {
        operations.add(operation);
      }
    }

    return operations;
  }
}
