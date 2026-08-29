part of 'document.dart';

/// Publishes what a handler's observable state did, one event per [Change].
///
/// A consumer subscribes with [watch], seeds its projection from the first
/// [HandlerReset] and moves it with the [HandlerDelta] events that follow. It
/// never has to read [value] again.
///
/// **A delta is a local observation of how this document's copy moved**, in the
/// order this document folded the changes in. That is **not** the replay order,
/// so two peers holding the same state can see two different delta sequences.
base mixin DeltaProvider<V, D extends ComposableDelta<D>> on DocumentConsumer {
  /// The current observable value, the one the deltas describe.
  V get value;

  /// The stream of what happened to this handler, opening with
  /// `HandlerReset(ResetCause.initial)`.
  ///
  /// ## When the events arrive
  ///
  /// As the document settles, before the call that changed it returns — so
  /// `importChanges` hands back a document whose watchers already know.
  ///
  /// A listener therefore runs while the document is idle: it may read
  /// anything, and it may **write**. What it writes reaches every listener in
  /// the same pass, after it returns, never inside its own callback.
  ///
  /// The opening reset is the exception, arriving one microtask later because
  /// the listener is still being wired up. Events published in between wait
  /// behind it.
  ///
  /// ## What it costs
  ///
  /// A remote change to an unwatched handler is queued and folded at the next
  /// read. A watched one cannot wait for a read that may never come, so it
  /// decodes and applies on **arrival**. Same work, different moment.
  ///
  /// Throws [DocumentDisposedException] on a disposed document, rather than
  /// returning a stream that could never fire again.
  Stream<HandlerUpdate<D>> watch() {
    _document._ensureNotDisposed('watch');
    final hub =
        _deltaHub as _DeltaHub<D>? ?? (_deltaHub = _DeltaHub<D>(_document));
    return hub.watch();
  }

  /// The point the stream has reached, without reading [value].
  ///
  /// For a consumer that **writes**: it already knows what it wrote, so it can
  /// move its copy by hand and take this number instead of paying for a read.
  /// A change publishes while it is being applied, so this covers that write
  /// straight after it. A consumer that only observes wants [readSynced].
  int get deltaSeq => _deltaHub?.seq ?? 0;

  /// The current [value] together with the point of the stream it reflects.
  ///
  /// The answer to a [HandlerReset]: adopt [DeltaSyncPoint.value], remember
  /// [DeltaSyncPoint.seq], and drop every [HandlerDelta] whose
  /// [HandlerUpdate.seq] it already covers.
  ///
  /// One operation, not two: an event landing in between would be applied
  /// twice. The value it hands back is one the caller **owns** — see
  /// [copyValue].
  DeltaSyncPoint<V> readSynced() {
    // The read first: it can fold queued changes in, which moves the sequence.
    final read = value;
    return DeltaSyncPoint<V>(
      value: copyValue(read),
      seq: _deltaHub?.seq ?? 0,
    );
  }

  /// The value [base] becomes once [delta] is applied.
  V applyDelta(V base, D delta);

  /// A copy of [value] that the caller owns; [readSynced] goes through it.
  ///
  /// A handler folds a change into its cached state **in place**. A consumer
  /// holding that state itself would find the change already in its base and
  /// then apply the delta on top of it — twice. Override it whenever [value]
  /// exposes the cached state; a handler that builds a fresh value on every
  /// read can keep this default.
  V copyValue(V value) => value;
}

/// What a [DocumentConsumer] delegates its delta bookkeeping to.
///
/// It exists so the hooks the cache paths call can live on [DocumentConsumer]
/// alone: two mixins of one class cannot both declare the same private name.
abstract class _DeltaHubBase {
  bool get hasListener;

  int get seq;

  DeltaSink<Object?>? begin();

  void bufferDelta(OperationId stamp);

  void publishRemoteDelta(Change change);

  void publishBufferedUpTo(Change change);

  void clear();

  void emitReset(ResetCause cause);

  void close();
}

/// Holds the stream, the sequence number and the deltas waiting for a change.
///
/// It is also the [DeltaSink] handed to the operation being applied, so what
/// that operation reports lands straight in [_staged].
final class _DeltaHub<D extends ComposableDelta<D>> extends _DeltaHubBase
    implements DeltaSink<D> {
  _DeltaHub(this._document);

  /// Where the events wait until the document is settled.
  final BaseCRDTDocument _document;

  StreamController<HandlerUpdate<D>>? _controller;
  int _seq = 0;

  /// What the operation being applied has reported so far, as one delta.
  ///
  /// An operation may write here and then refuse itself, describing a state
  /// nobody holds; [clear] drops it before it can leave.
  D? _staged;

  /// The deltas of the open transaction, in apply order. They wait because the
  /// change carrying them is created on commit, after compaction may have
  /// fused them.
  List<(OperationId stamp, D delta)>? _buffer;

  @override
  bool get hasListener => _controller?.hasListener ?? false;

  @override
  int get seq => _seq;

  Stream<HandlerUpdate<D>> watch() {
    // Synchronous: the outbox has already deferred this to the moment the
    // document is settled, which is also the only place allowed to add to a
    // synchronous controller.
    final source = (_controller ??=
            StreamController<HandlerUpdate<D>>.broadcast(sync: true))
        .stream;

    late StreamController<HandlerUpdate<D>> out;
    StreamSubscription<HandlerUpdate<D>>? subscription;

    // A synchronous controller would hand the opening reset to a listener that
    // is still being wired up, so it goes one microtask later. Whatever is
    // published in between waits here: the reset comes first.
    var opened = false;
    var waiting = <HandlerUpdate<D>>[];

    out = StreamController<HandlerUpdate<D>>(
      sync: true,
      onListen: () {
        final reset = HandlerReset<D>(cause: ResetCause.initial, seq: ++_seq);
        subscription = source.listen(
          (update) => opened ? out.add(update) : waiting.add(update),
          onError: out.addError,
          onDone: out.close,
        );
        scheduleMicrotask(() {
          if (out.isClosed) {
            return;
          }
          opened = true;
          final held = waiting;
          waiting = <HandlerUpdate<D>>[];
          out.add(reset);
          for (final update in held) {
            if (out.isClosed) {
              return;
            }
            out.add(update);
          }
        });
      },
      onCancel: () => subscription?.cancel(),
    );

    return out.stream;
  }

  @override
  void add(D delta) {
    final current = _staged;
    _staged = current == null ? delta : current.compose(delta);
  }

  @override
  DeltaSink<Object?>? begin() {
    if (!hasListener) {
      return null;
    }
    _staged = null;
    return this;
  }

  /// What the operation reported, clearing the slot for the next one.
  D? _takeStaged() {
    final staged = _staged;
    _staged = null;
    return staged;
  }

  @override
  void bufferDelta(OperationId stamp) {
    final staged = _takeStaged();
    if (staged == null) {
      return;
    }
    (_buffer ??= <(OperationId, D)>[]).add((stamp, staged));
  }

  @override
  void publishRemoteDelta(Change change) {
    final staged = _takeStaged();
    if (staged == null) {
      return;
    }
    _emitDelta(change, staged);
  }

  @override
  void publishBufferedUpTo(Change change) {
    final buffer = _buffer;
    if (buffer == null || buffer.isEmpty) {
      return;
    }

    // Compaction fuses only adjacent operations of one handler, and gives the
    // result the stamp of the later one. So everything waiting that is not
    // newer than this change is exactly what this change carries.
    D? composed;
    var taken = 0;
    while (
        taken < buffer.length && buffer[taken].$1.compareTo(change.id) <= 0) {
      final next = buffer[taken].$2;
      composed = composed == null ? next : composed.compose(next);
      taken++;
    }
    if (taken == 0) {
      return;
    }
    buffer.removeRange(0, taken);
    if (buffer.isEmpty) {
      _buffer = null;
    }

    _emitDelta(change, composed!);
  }

  @override
  void clear() {
    _staged = null;
    _buffer = null;
  }

  @override
  void emitReset(ResetCause cause) {
    if (!hasListener) {
      return;
    }
    _emit(HandlerReset<D>(cause: cause, seq: ++_seq));
  }

  @override
  void close() {
    _controller?.close();
    _controller = null;
  }

  void _emitDelta(Change change, D delta) {
    _emit(
      HandlerDelta<D>(
        delta: delta,
        changeId: change.id,
        author: change.author,
        // From the change, not from the publishing path: `createChange`
        // writes locally but publishes through the remote one.
        local: change.author == _document.peerId,
        origin: _document._deltaOrigin,
        seq: ++_seq,
      ),
    );
  }

  void _emit(HandlerUpdate<D> update) {
    final controller = _controller;
    if (controller == null || controller.isClosed) {
      return;
    }
    // Published now, handed out once the document is settled (see
    // `_deltaOutbox`). The sequence number is already spent, so `deltaSeq` is
    // truthful even before this event lands.
    _document._enqueueDeltaEvent(() {
      if (!controller.isClosed) {
        controller.add(update);
      }
    });
  }
}
