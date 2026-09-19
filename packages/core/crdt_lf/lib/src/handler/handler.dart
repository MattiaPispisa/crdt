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
/// - the `spec` its constructor passes up — required: what kind of handler this
///   is, so a peer that receives a reference to one can rebuild it.
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
abstract base class Handler<T>
    with DocumentConsumer, SnapshotProvider, CacheableStateProvider<T> {
  /// Creates a handler of the kind [spec] names, registered on [doc].
  ///
  /// {@macro handler_spec}
  Handler(this.doc, {required HandlerSpec<Handler<dynamic>> spec})
      : _instanceSpec = spec {
    doc._registerHandler(this);
  }

  /// The document that owns this handler
  final BaseCRDTDocument doc;

  /// The kind this handler is. Read by [BaseCRDTDocument] as it registers.
  final HandlerSpec<Handler<dynamic>> _instanceSpec;

  /// The decoders this handler owns, keyed by [OperationEnvelope.kind].
  ///
  /// A kind not in this map is refused with [UnknownOperationKindException]
  /// when a change carrying it is decoded.
  OperationDecoders get operationDecoders;

  /// The version of the blob [getSnapshotState] writes.
  ///
  /// Raise it when the layout changes, and write it with [snapshotHeader]: a
  /// peer that cannot read the version is refused the blob whole.
  int get snapshotBlobVersion => 1;

  /// The oldest blob version this build still reads.
  ///
  /// Defaults to [snapshotBlobVersion], which refuses a blob from any other
  /// build. Lower it to keep reading an older layout, and branch on the version
  /// [readSnapshotHeader] returns.
  int get minReadableSnapshotBlobVersion => snapshotBlobVersion;

  /// A builder holding the head of this handler's snapshot blob.
  ///
  /// ```dart
  /// @override
  /// Uint8List getSnapshotState() {
  ///   final out = snapshotHeader()..add(Wtf8.encode(value));
  ///   return out.toBytes();
  /// }
  /// ```
  BytesBuilder snapshotHeader() =>
      BytesBuilder(copy: false)..addByte(snapshotBlobVersion);

  /// The version at the head of [bytes], and the offset of what follows it.
  ///
  /// Throws a [FormatException] naming this handler when the version falls
  /// outside `minReadableSnapshotBlobVersion..snapshotBlobVersion`.
  ({int version, int offset}) readSnapshotHeader(Uint8List bytes) =>
      SnapshotBlob.read(
        bytes,
        min: minReadableSnapshotBlobVersion,
        max: snapshotBlobVersion,
        name: handlerType,
      );

  /// {@macro handler_type_tag}
  ///
  /// Used as the type tag in operation envelopes, in the snapshot handler
  /// manifest and in [HandlerRef]s, and as the key the kind is registered
  /// under. The same value is produced on every peer, so changes route to the
  /// matching handler and nested handlers can be reconstructed remotely.
  String get handlerType => _instanceSpec.type;

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

  /// [accumulator] and [current] fused into one operation, or `null` when they
  /// cannot be.
  ///
  /// Called on consecutive operations inside a transaction. The default fuses
  /// nothing.
  ///
  /// Return [current] or a fresh operation, never [accumulator]: the result
  /// takes the stamp of the later one, and an earlier stamp strands the deltas
  /// that change also carries.
  Operation? compound(Operation accumulator, Operation current) => null;

  /// Whether this handler can build the inverse of its own operations.
  ///
  /// [CRDTUndoManager.track] refuses a handler that answers `false`. A handler
  /// that indexes by position alone has no identity to anchor an inverse to.
  bool get invertible => false;

  /// The operations that undo [operation], against the state as it is
  /// **before** [operation] is applied. Empty when there is nothing to undo.
  ///
  /// [Operation.stamp] is readable here. Name CRDT identities — element ids,
  /// keys, tags — never positions, so the undo stays right when other peers
  /// edited the same handler in between.
  ///
  /// Return fresh, unstamped operations, in the order they have to be applied.
  List<Operation> invert(Operation operation) => const [];

  /// [operation], an inverse built by [invert], made ready to be written now.
  ///
  /// An inverse is built long before it is written, and in between an element
  /// it names may have come back under a new identity. Override this to follow
  /// them; the default returns [operation] unchanged.
  ///
  /// Return [operation] or a fresh unstamped operation, never one already
  /// written.
  Operation prepareInverse(Operation operation) => operation;

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
