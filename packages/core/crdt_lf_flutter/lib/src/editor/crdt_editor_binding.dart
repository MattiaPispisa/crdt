// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/src/provider/handler_delta_subscription.dart';

/// Keeps an editor and one handler in step, both ways.
///
/// [V] and [D] are the value and the delta the handler publishes. The editor
/// holds its own copy of the content: the binding moves it with [onReset] and
/// [onRemoteDelta], and writes the local edits through [push]. It has no
/// widget; `CrdtEditorBinder` owns one for a subtree. See the README, "Editor
/// bindings".
class CrdtEditorBinding<V, D extends ComposableDelta<D>> {
  /// Creates a binding that follows no handler until [attach].
  ///
  /// [resolve] finds the handler; the default throws a `FlutterError` when
  /// the id holds no handler of the `<V, D>` shape.
  CrdtEditorBinding({
    required this.onRemoteDelta,
    required this.onReset,
    this.verifyProjection,
    this.skipEmptyDeltas = true,
    DeltaProviderResolver<V, D>? resolve,
  }) : _resolve = resolve ??
            ((document, id) =>
                resolveDeltaProvider<V, D>(document, id, 'CrdtEditorBinding'));

  /// Applies one change of the handler to the editor.
  ///
  /// Never called for a write made inside [push].
  final void Function(HandlerDelta<D> delta) onRemoteDelta;

  /// Replaces the whole editor content with `value`; `cause` says why.
  ///
  /// The value belongs to the editor: it needs no copy.
  final void Function(V value, ResetCause cause) onReset;

  /// Whether the editor still shows what the handler holds; `null` to skip
  /// the check.
  ///
  /// Asked after each remote delta and each [push], once the editor has
  /// caught up with the stream. On `false` the binding reads the handler and
  /// calls [onReset] with [ResetCause.deltasMissed]. It runs on every change,
  /// so keep it cheap (a length, not the whole value).
  final bool Function()? verifyProjection;

  /// Whether [onRemoteDelta] skips a delta that changes nothing. Defaults to
  /// `true`.
  final bool skipEmptyDeltas;

  final DeltaProviderResolver<V, D> _resolve;

  late final HandlerDeltaSubscription<V, D> _subscription =
      HandlerDeltaSubscription<V, D>(
    resolve: _resolve,
    onReset: _onReset,
    onDelta: _onDelta,
    isAlive: () => _document != null,
    seed: true,
  );

  CRDTDocument? _document;
  String? _id;
  bool _disposed = false;

  bool _pushing = false;
  ResetCause? _resetWhilePushing;

  /// The document of the followed handler; `null` while detached.
  CRDTDocument? get document => _document;

  /// The id of the followed handler; `null` while detached.
  String? get id => _id;

  /// Whether the binding follows a handler.
  bool get isAttached => _document != null;

  /// The followed handler. Throws before the first [attach].
  DeltaProvider<V, D> get provider => _subscription.provider;

  /// Whether the handler has published changes the editor has not received
  /// yet.
  ///
  /// `true` in the middle of a burst: a batch publishes at once and is handed
  /// out one change at a time.
  bool get isBehind => _subscription.publishedSeq != _subscription.synced;

  /// Reads the handler value, and counts every change it holds as received.
  ///
  /// The editor must take the value in: the changes it covers never reach
  /// [onRemoteDelta]. Throws before the first [attach].
  V readSynced() => _subscription.readSynced().value;

  /// Follows the handler registered under [id] on [document].
  ///
  /// A no-op when it already follows them. Otherwise it leaves the old
  /// handler, calls [onBeforeAttach], reads the new one and calls [onReset]
  /// with [ResetCause.initial] before it returns.
  ///
  /// Throws a [StateError] after [dispose].
  void attach(
    CRDTDocument document,
    String id, {
    void Function()? onBeforeAttach,
  }) {
    if (_disposed) {
      throw StateError('CrdtEditorBinding.attach called after dispose');
    }
    final point = _subscription.syncTo(
      document,
      id,
      onBeforeAttach: () {
        _resetWhilePushing = null;
        onBeforeAttach?.call();
      },
    );
    _document = document;
    _id = id;
    if (point != null) {
      onReset(point.value, ResetCause.initial);
    }
  }

  /// Stops following the handler; the callbacks stop too.
  ///
  /// A later [attach] follows again, the same handler included.
  void detach() {
    _subscription.cancel();
    _document = null;
    _id = null;
    _resetWhilePushing = null;
  }

  /// Detaches for good: a later [attach] throws.
  void dispose() {
    detach();
    _disposed = true;
  }

  /// Reads the handler and calls [onReset] with [cause]; a no-op while
  /// detached.
  void resync(ResetCause cause) {
    if (_document == null) {
      return;
    }
    _reset(cause);
  }

  /// Runs [writeToHandler], the write of one local edit into the handler.
  ///
  /// Put a write of several operations in one `runInTransaction`, so the edit
  /// is one document update. While it runs, every delta of the handler is
  /// dropped: the echo of the write, and also a change another watcher writes
  /// back from inside it. That change carries the same origin as the echo and
  /// describes the old editor content, so an origin check cannot tell them
  /// apart; [verifyProjection] finds it afterwards. A reset that arrives
  /// meanwhile is delivered after the write.
  ///
  /// When the editor [isBehind], the binding reads the handler after the
  /// write and calls [onReset] with [ResetCause.deltasMissed].
  ///
  /// A push inside a push runs the write at once. A no-op while detached or
  /// when the handler is deleted.
  void push(void Function() writeToHandler) {
    final document = _document;
    final id = _id;
    if (document == null || id == null || document.isDeleted(id)) {
      return;
    }
    if (_pushing) {
      writeToHandler();
      return;
    }

    // Read before the write, which moves the stream itself. Mid-burst the
    // editor misses events the handler holds: marking synced would drop them.
    final behind = isBehind;

    // Set before the write: its echo is delivered inside it, synchronously.
    _pushing = true;
    try {
      writeToHandler();
    } finally {
      _pushing = false;
    }
    if (_document == null) {
      return;
    }
    // After the write: the editor holds its own edit, and the deltas dropped
    // during it are counted as received.
    _subscription.markSyncedToPublished();

    final postponed = _resetWhilePushing;
    _resetWhilePushing = null;
    if (postponed != null || behind) {
      // A reset read mid-write cannot see the edit: read again now.
      _reset(postponed ?? ResetCause.deltasMissed);
      return;
    }
    _verify();
  }

  void _onReset(DeltaSyncPoint<V> point, ResetCause cause) {
    if (_pushing) {
      _resetWhilePushing = cause;
      return;
    }
    onReset(point.value, cause);
  }

  void _onDelta(HandlerDelta<D> event) {
    if (_pushing || (skipEmptyDeltas && event.delta.isEmpty)) {
      return;
    }
    onRemoteDelta(event);
    _verify();
  }

  void _verify() {
    final verify = verifyProjection;
    if (verify == null ||
        _document == null ||
        _subscription.synced != _subscription.publishedSeq) {
      return;
    }
    if (verify()) {
      return;
    }
    _reset(ResetCause.deltasMissed);
  }

  void _reset(ResetCause cause) {
    onReset(readSynced(), cause);
  }
}
