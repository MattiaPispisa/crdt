// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:async';

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
  List<D>? _dropped;
  ResetCause? _resetWhilePushing;

  // Ends a push whose echo waits for the flush of an outer transaction.
  void Function()? _finishPush;

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
        _endPush();
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
  /// back from inside it. While the write runs the binding cannot tell that
  /// change from the echo: a write needs no origin, so the origin cannot mark
  /// the echo. [isEcho] and [verifyProjection] find it afterwards. A reset that
  /// arrives meanwhile is delivered after the write.
  ///
  /// When the editor [isBehind], the binding reads the handler after the
  /// write and calls [onReset] with [ResetCause.deltasMissed].
  ///
  /// [isEcho] tells whether the deltas dropped during the write are only what
  /// the write itself made. When it says no, a foreign change was dropped, and
  /// the binding reads the handler after the write like for a postponed reset.
  /// This sees a foreign change that keeps the content length, which
  /// [verifyProjection] cannot.
  ///
  /// In an open `runInTransaction`, the echo goes out when that transaction
  /// flushes: the deltas are dropped until then, and the checks above run
  /// then. A push made while the document delivers events has its echo
  /// delivered after the listener returns, so [isEcho] sees none of it and the
  /// binding reads the handler. The editor stays right, at the cost of a read.
  ///
  /// [ownStep] makes the write an undo step of its own on that manager, apart
  /// from the typing around it. Pass it for a format.
  ///
  /// A push inside a push runs the write at once. A no-op while detached or
  /// when the handler is deleted.
  void push(
    void Function() writeToHandler, {
    bool Function(List<D> dropped)? isEcho,
    CRDTUndoManager? ownStep,
  }) {
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

    // Set before the write: a flush it makes delivers its echo inside it.
    _pushing = true;
    final dropped = _dropped = isEcho == null ? null : [];

    void finish() {
      _endPush();
      if (_document == null) {
        return;
      }
      // After the write: the editor holds its own edit, and the deltas dropped
      // during it are counted as received.
      _subscription.markSyncedToPublished();

      final postponed = _resetWhilePushing;
      _resetWhilePushing = null;
      final foreign = dropped != null && !isEcho!(dropped);
      if (postponed != null || behind || foreign) {
        // A reset read mid-write cannot see the edit: read again now.
        _reset(postponed ?? ResetCause.deltasMissed);
        return;
      }
      _verify();
    }

    var written = false;
    ownStep?.stopCapturing();
    try {
      writeToHandler();
      written = true;
    } finally {
      if (!written) {
        _endPush();
      }
    }
    ownStep?.stopCapturing();
    if (_document == null || !document.isInTransaction) {
      finish();
      return;
    }
    _finishPush = finish;
    // The transaction body is synchronous, so this runs after its flush. No
    // delta ends a push that published nothing.
    scheduleMicrotask(() {
      if (identical(_finishPush, finish)) {
        finish();
      }
    });
  }

  void _endPush() {
    _pushing = false;
    _dropped = null;
    _finishPush = null;
  }

  void _finishPushIfFlushed() {
    final finish = _finishPush;
    if (finish != null && !isBehind && !_document!.isInTransaction) {
      finish();
    }
  }

  void _onReset(DeltaSyncPoint<V> point, ResetCause cause) {
    if (_pushing) {
      _resetWhilePushing = cause;
      _finishPushIfFlushed();
      return;
    }
    onReset(point.value, cause);
  }

  void _onDelta(HandlerDelta<D> event) {
    _dropped?.add(event.delta);
    if (_pushing) {
      _finishPushIfFlushed();
      return;
    }
    if (skipEmptyDeltas && event.delta.isEmpty) {
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
