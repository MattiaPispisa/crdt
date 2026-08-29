part of 'document.dart';

/// Publishes what a handler's observable state did, one event per [Change].
///
/// A consumer subscribes with [watch], seeds its projection from the
/// [HandlerReset] that arrives first, and keeps it up to date from the
/// [HandlerDelta] events that follow.
/// **It never has to read [value] again.**
///
/// **A delta is a local observation of how this
/// document's copy moved**, in the order this document folded the changes in.
/// That order is **not** the replay order, so two peers holding the same state
/// can observe two different sequences of deltas.
base mixin DeltaProvider<V, D extends ComposableDelta<D>> on DocumentConsumer {
  /// The current observable value, the one the deltas describe.
  V get value;

  /// The stream of what happened to this handler.
  ///
  /// The first event is always `HandlerReset(ResetCause.initial)`, so a
  /// consumer exercises its reset path immediately instead of months later.
  ///
  /// ## When the events arrive
  ///
  /// As the document settles, before the call that changed it returns. So
  /// `importChanges` hands back a document whose watchers already know, and
  /// there is no window where a change exists and a projection still shows the
  /// text before it.
  ///
  /// A listener runs when the document is idle, never in the middle of its
  /// work, so it is free to read anything. It is also free to **write**: what
  /// it writes reaches every listener in the same pass, after it returns —
  /// never inside its own callback.
  ///
  /// The opening reset is the exception: it arrives one microtask later,
  /// because at the moment `listen` is called the listener is still being
  /// wired up. Anything published in between waits behind it, so a reset still
  /// comes first.
  ///
  /// ## What it costs
  ///
  /// A handler nobody reads normally costs nothing: a remote change is queued
  /// and folded in at the next read (lazy evaluation).
  /// A watched handler cannot wait for a read
  /// that may never come, so it pays
  /// the decode and the apply when the change **arrives** (eager).
  /// The work is the same; only the moment changes.
  Stream<HandlerUpdate<D>> watch() {
    // A disposed document publishes nothing ever again, so handing back a
    // stream that opens with a reset and then stays silent forever would be a
    // lie. Say so instead.
    _document._ensureNotDisposed('watch');
    final hub =
        _deltaHub as _DeltaHub<D>? ?? (_deltaHub = _DeltaHub<D>(_document));
    return hub.watch();
  }

  /// The point the stream has reached, without reading [value].
  ///
  /// [readSynced] answers "what is the value, and which events does it already
  /// hold?" in one step, which is what a consumer that only **observes**
  /// needs.
  ///
  /// A consumer that also **writes** already knows what it wrote. After its
  /// own change it can move its copy by hand and then take this number,
  /// saying "I account for everything published so far" — without paying for
  /// a read it does not need. A change publishes its events while it is being
  /// applied, so reading this straight after a write covers that write.
  int get deltaSeq => _deltaHub?.seq ?? 0;

  /// The current [value] together with the point of the stream it reflects.
  ///
  /// This is the answer to a [HandlerReset]: adopt [DeltaSyncPoint.value],
  /// remember [DeltaSyncPoint.seq], and drop every [HandlerDelta] whose
  /// [HandlerUpdate.seq] is less than or equal to it.
  ///
  /// Reading the value and learning where it sits in the stream is one
  /// operation on purpose. Two operations would let an event land in between,
  /// and the consumer would apply it twice.
  ///
  /// The value it hands back is one the caller **owns**: see [copyValue].
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

  /// A copy of [value] that the caller owns.
  ///
  /// [readSynced] goes through this, and it has to: a handler folds a change
  /// into its cached state **in place**, while the [HandlerDelta] describing
  /// that change is delivered a microtask later. A consumer holding the state
  /// itself would therefore find the change already inside its base, and then
  /// apply the delta on top of it — twice.
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
  /// An operation may write here and then refuse itself (see
  /// [CacheableStateProvider.incrementCachedState]). What it wrote describes a
  /// state nobody holds, so [clear] drops it and it never leaves.
  D? _staged;

  /// The deltas of the operations of the open transaction, in the order they
  /// were applied. They wait because the change that carries them is created
  /// on commit, after the compaction that may have fused them.
  List<(OperationId stamp, D delta)>? _buffer;

  @override
  bool get hasListener => _controller?.hasListener ?? false;

  @override
  int get seq => _seq;

  Stream<HandlerUpdate<D>> watch() {
    // Synchronous: the outbox has already put this off to the moment the
    // document is settled, so there is nothing left to wait for. Adding to it
    // anywhere but from the flush is what a synchronous controller forbids,
    // and the outbox is what makes sure nothing does.
    final source = (_controller ??=
            StreamController<HandlerUpdate<D>>.broadcast(sync: true))
        .stream;

    late StreamController<HandlerUpdate<D>> out;
    StreamSubscription<HandlerUpdate<D>>? subscription;

    // The opening reset cannot go out from inside [onListen]: a synchronous
    // controller would hand it to a listener that is still being wired up. It
    // goes one microtask later instead, and anything the document publishes in
    // between waits here, because this stream promises a reset first.
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
    _emitDelta(change, staged, local: false);
  }

  @override
  void publishBufferedUpTo(Change change) {
    final buffer = _buffer;
    if (buffer == null || buffer.isEmpty) {
      return;
    }

    // Compaction only fuses operations that sit next to each other and belong
    // to one handler, and it hands the fused operation the stamp of the later
    // one. So everything still waiting that is not newer than this change is
    // exactly what this change carries.
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

    _emitDelta(change, composed!, local: true);
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

  void _emitDelta(Change change, D delta, {required bool local}) {
    _emit(
      HandlerDelta<D>(
        delta: delta,
        changeId: change.id,
        author: change.author,
        local: local,
        seq: ++_seq,
      ),
    );
  }

  void _emit(HandlerUpdate<D> update) {
    final controller = _controller;
    if (controller == null || controller.isClosed) {
      return;
    }
    // Published now, handed out once the document is settled — see
    // [BaseCRDTDocument._deltaOutbox] for why the two are not the same moment.
    // The sequence number is already spent, so a consumer that asks how far
    // the stream has got is told the truth even before this event reaches it.
    _document._enqueueDeltaEvent(() {
      if (!controller.isClosed) {
        controller.add(update);
      }
    });
  }
}
