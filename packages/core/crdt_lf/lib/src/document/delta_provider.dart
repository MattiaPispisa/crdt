part of 'document.dart';

/// Publishes what a handler's observable state did, one event per [Change].
///
/// A consumer subscribes with [watch], seeds its projection from the
/// [HandlerReset] that arrives first, and keeps it up to date from the
/// [HandlerDelta] events that follow. It never has to read [value] again.
///
/// Nothing here reaches the wire. A delta is a local observation of how this
/// document's copy moved, in the order this document folded the changes in.
/// That order is **not** the replay order, so two peers holding the same state
/// can observe two different sequences of deltas.
///
/// Everything costs one `null` check while nobody is watching: the apply path
/// is handed no sink and no event is built.
base mixin DeltaProvider<V, D extends ComposableDelta<D>> on DocumentConsumer {
  /// The current observable value, the one the deltas describe.
  V get value;

  /// The stream of what happened to this handler.
  ///
  /// The first event is always `HandlerReset(ResetCause.initial)`, so a
  /// consumer exercises its reset path immediately instead of months later.
  ///
  /// ## What it costs
  ///
  /// A handler nobody reads normally costs nothing: a remote change is queued
  /// and folded in at the next read (see `doc/incremental_remote_apply.md`).
  /// A watched handler cannot wait for a read that may never come, so it pays
  /// the decode and the apply when the change **arrives**. The work is the
  /// same; only the moment changes.
  Stream<HandlerUpdate<D>> watch() {
    final hub = _deltaHub as _DeltaHub<D>? ?? (_deltaHub = _DeltaHub<D>());
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
  DeltaSyncPoint<V> readSynced() {
    // The read first: it can fold queued changes in, which moves the sequence.
    final read = value;
    return DeltaSyncPoint<V>(value: read, seq: _deltaHub?.seq ?? 0);
  }
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

  void publishDelta(Change change, {required bool local});

  void publishBufferedUpTo(Change change);

  void clear();

  void emitReset(ResetCause cause);

  void close();
}

/// Holds the stream, the sequence number and the deltas waiting for a change.
final class _DeltaHub<D extends ComposableDelta<D>> extends _DeltaHubBase {
  StreamController<HandlerUpdate<D>>? _controller;
  int _seq = 0;

  /// The deltas of the operation being applied right now.
  _DeltaStage<D>? _stage;

  /// The deltas of the operations of the open transaction, in the order they
  /// were applied. They wait because the change that carries them is created
  /// on commit, after the compaction that may have fused them.
  List<_BufferedDelta<D>>? _buffer;

  @override
  bool get hasListener => _controller?.hasListener ?? false;

  @override
  int get seq => _seq;

  Stream<HandlerUpdate<D>> watch() {
    final source =
        (_controller ??= StreamController<HandlerUpdate<D>>.broadcast()).stream;

    late StreamController<HandlerUpdate<D>> out;
    StreamSubscription<HandlerUpdate<D>>? subscription;

    out = StreamController<HandlerUpdate<D>>(
      onListen: () {
        // Both steps run in this one turn, and [out] buffers, so no event can
        // slip between the reset and the moment [source] is listened to.
        out.add(HandlerReset<D>(cause: ResetCause.initial, seq: ++_seq));
        subscription = source.listen(
          out.add,
          onError: out.addError,
          onDone: out.close,
        );
      },
      onCancel: () => subscription?.cancel(),
    );

    return out.stream;
  }

  @override
  DeltaSink<Object?>? begin() {
    if (!hasListener) {
      return null;
    }
    return _stage = _DeltaStage<D>();
  }

  @override
  void bufferDelta(OperationId stamp) {
    final staged = _stage?.composed;
    _stage = null;
    if (staged == null) {
      return;
    }
    (_buffer ??= <_BufferedDelta<D>>[])
        .add(_BufferedDelta<D>(stamp: stamp, delta: staged));
  }

  @override
  void publishDelta(Change change, {required bool local}) {
    final staged = _stage?.composed;
    _stage = null;
    if (staged == null) {
      return;
    }
    _emit(
      HandlerDelta<D>(
        delta: staged,
        changeId: change.id,
        author: change.author,
        local: local,
        seq: ++_seq,
      ),
    );
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
    while (taken < buffer.length &&
        buffer[taken].stamp.compareTo(change.id) <= 0) {
      final next = buffer[taken].delta;
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

    _emit(
      HandlerDelta<D>(
        delta: composed!,
        changeId: change.id,
        author: change.author,
        local: true,
        seq: ++_seq,
      ),
    );
  }

  @override
  void clear() {
    _stage = null;
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

  void _emit(HandlerUpdate<D> update) {
    final controller = _controller;
    if (controller != null && !controller.isClosed) {
      controller.add(update);
    }
  }
}

/// Collects the deltas of one operation, so a half-applied operation can be
/// thrown away whole.
///
/// An operation may mutate the state in place and then refuse it (see
/// [CacheableStateProvider.incrementCachedState]). Whatever it wrote to the
/// sink before refusing describes a state nobody holds, so it never leaves
/// here.
final class _DeltaStage<D extends ComposableDelta<D>> implements DeltaSink<D> {
  D? _composed;

  /// Everything this operation reported, as one delta.
  D? get composed => _composed;

  @override
  void add(D delta) {
    final current = _composed;
    _composed = current == null ? delta : current.compose(delta);
  }
}

/// One operation's delta, waiting for the change that will carry it.
final class _BufferedDelta<D extends ComposableDelta<D>> {
  const _BufferedDelta({required this.stamp, required this.delta});

  /// The id of the operation the delta came from.
  final OperationId stamp;

  /// What the operation did.
  final D delta;
}
