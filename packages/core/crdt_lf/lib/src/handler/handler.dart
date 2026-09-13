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
/// - `spec` on the constructor — for a handler that syncs, persists, or must
///   survive dart2js minification. It fixes the type tag and tells the document
///   how to rebuild the handler.
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
  /// [spec] is how this kind of handler is rebuilt. It does two things at once:
  /// it fixes the type tag, and it tells [doc] how to build a handler of this
  /// kind — which is what a peer resolving a [HandlerRef] needs, and what
  /// [CRDTDocument.reconstruct] walks.
  ///
  /// Leave it out and the handler still works, under a tag derived from
  /// `runtimeType`: that is the flat mode, where every peer creates the same
  /// ids by hand. Nothing can rebuild it, and the tag does not survive dart2js.
  Handler(this.doc, {HandlerSpec<Handler<dynamic>>? spec}) : _spec = spec {
    doc._registerHandler(this);
  }

  /// The document that owns this handler
  final BaseCRDTDocument doc;

  final HandlerSpec<Handler<dynamic>>? _spec;

  /// How to rebuild a handler of this kind; `null` when this build cannot say.
  ///
  /// The document reads it when the handler registers, so a handler that
  /// answers one declares its own type — which is what a peer resolving a
  /// [HandlerRef] needs, and what [CRDTDocument.reconstruct] walks.
  ///
  /// Defaults to the `spec` passed to the constructor. A class whose tag is
  /// fixed overrides it with its own constant instead, so opening one declares
  /// the type with nothing registered.
  HandlerSpec<Handler<dynamic>>? get handlerSpec => _spec;

  /// The decoders this handler owns, keyed by [OperationEnvelope.kind].
  ///
  /// A kind not in this map is refused with [UnknownOperationKindException]
  /// when a change carrying it is decoded.
  OperationDecoders get operationDecoders;

  /// The version of the blob [getSnapshotState] writes.
  ///
  /// Raising it tells the other peers that they cannot read what this build
  /// writes, unless they raised [minReadableSnapshotBlobVersion] to match.
  ///
  /// It only means that when the blob actually carries it, which is what
  /// [snapshotHeader] and [readSnapshotHeader] are for. A handler that writes
  /// its state without them still answers `1` here, and two such handlers with
  /// genuinely different layouts both claim `1` and look compatible — so a
  /// handler that skips the header opts out of this check rather than passing
  /// it.
  int get snapshotBlobVersion => 1;

  /// The oldest blob version this build still reads.
  ///
  /// Defaults to [snapshotBlobVersion]: a handler reads only what it writes,
  /// and a blob from any other build is refused. Lower it to keep reading an
  /// older layout and migrate it on the way in. [readSnapshotHeader] hands
  /// back the version it found, so wherever the handler reads [lastSnapshot]
  /// back it can branch on it:
  ///
  /// ```dart
  /// @override
  /// int get snapshotBlobVersion => 2;
  /// @override
  /// int get minReadableSnapshotBlobVersion => 1;
  ///
  /// final head = readSnapshotHeader(bytes);
  /// final state = head.version == 1
  ///     ? _readV1(bytes, head.offset)
  ///     : _readV2(bytes, head.offset);
  /// ```
  ///
  /// The next [getSnapshotState] writes [snapshotBlobVersion], so the old
  /// layout leaves the document at the first snapshot after the upgrade.
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

  /// Checks the head [snapshotHeader] wrote and returns the version it
  /// carries, with the offset of what follows it.
  ///
  /// Branch on `version` to read an older layout; see
  /// [minReadableSnapshotBlobVersion].
  ///
  /// Throws a [FormatException] naming this handler when [bytes] falls outside
  /// `minReadableSnapshotBlobVersion..snapshotBlobVersion`.
  ({int version, int offset}) readSnapshotHeader(Uint8List bytes) =>
      SnapshotBlob.read(
        bytes,
        min: minReadableSnapshotBlobVersion,
        max: snapshotBlobVersion,
        name: handlerType,
      );

  /// Stable identifier of this handler's **type**.
  ///
  /// Used as the type tag in operation envelopes, in the snapshot handler
  /// manifest and in [HandlerRef]s, and as the key under which a
  /// [HandlerSpec] is registered (see [BaseCRDTDocument.register]).
  /// The same value is produced on every peer so changes route to the matching
  /// handler and nested handlers can be reconstructed remotely.
  ///
  /// Defaults to `runtimeType.toString()`, which is convenient but **not
  /// stable under dart2js minification**. A handler that syncs or persists
  /// across builds must pass a [HandlerSpec] to the constructor instead; see
  /// [hasStableHandlerType], which is how the sync layer spots one that did
  /// not.
  ///
  /// A generic handler needs it most: its default tag carries the type
  /// argument (`CRDTListHandler<Todo>`), so the tag both changes with `T` and
  /// is minified away.
  String get handlerType => handlerSpec?.type ?? runtimeType.toString();

  /// Whether [handlerType] is a constant this build controls.
  ///
  /// `false` when it falls back to `runtimeType.toString()`. That tag works on
  /// the VM and in a debug web build, and then changes under dart2js
  /// minification in a Flutter web release — where a peer suddenly cannot
  /// route the changes it used to. `dart test -p chrome` does not minify, so
  /// it never catches this.
  ///
  /// `crdt_socket_sync` checks it before a handshake and refuses, in debug
  /// only, to let such a tag travel.
  bool get hasStableHandlerType => handlerSpec != null;

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

  /// Whether this handler can build the inverse of its own operations.
  ///
  /// A handler that indexes by position alone cannot: it has no element
  /// identity to anchor an inverse to, so the undo would land on the wrong
  /// element as soon as another peer edits the same sequence.
  ///
  /// [CRDTUndoManager.track] refuses a handler that answers `false`.
  bool get invertible => false;

  /// The operations that undo [operation], read against the state as it is
  /// **now** — that is, before [operation] is applied.
  ///
  /// The document calls this from [BaseCRDTDocument.registerOperation], after
  /// it mints the stamp and before it folds the operation in. So
  /// [Operation.stamp] is readable here, and the state has not moved yet.
  ///
  /// An inverse names CRDT identities — element ids, keys, tags — and never a
  /// position. That is what keeps an undo right when other peers edited the
  /// same handler in between.
  ///
  /// The returned operations are fresh and unstamped: the document stamps them
  /// when they are registered, and an operation is stamped once. Return them in
  /// the order they have to be applied.
  ///
  /// Returns an empty list when there is nothing to undo, which includes an
  /// operation with no observable effect.
  List<Operation> invert(Operation operation) => const [];

  /// [operation], an inverse built by [invert], made ready to be written now.
  ///
  /// An inverse is built the moment the operation it undoes is written, and
  /// written itself much later. In between, undoing a **later** step can
  /// rebuild elements this one names: an element cannot come back to life, so
  /// it comes back with a new identity, and an inverse holding the old one
  /// would miss it.
  ///
  /// A handler that rebuilds elements overrides this to follow them. The
  /// default returns [operation] unchanged.
  ///
  /// Return [operation] itself, or a fresh unstamped operation; never one that
  /// has been written already.
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
