// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/src/provider/handler_delta_subscription.dart';

class CrdtEditorBinding<V, D extends ComposableDelta<D>> {
  CrdtEditorBinding({
    required this.onRemoteDelta,
    required this.onReset,
    this.verifyProjection,
    DeltaProviderResolver<V, D>? resolve,
  }) : _resolve = resolve ??
            ((document, id) =>
                resolveDeltaProvider<V, D>(document, id, 'CrdtEditorBinding'));

  final void Function(HandlerDelta<D> delta) onRemoteDelta;

  final void Function(V value, ResetCause cause) onReset;

  final bool Function()? verifyProjection;

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

  // Dropped while set: our own echo and a foreign delta served inside our
  // write. `origin` cannot tell them apart, see the package CLAUDE.md.
  bool _pushing = false;
  ResetCause? _resetWhilePushing;

  CRDTDocument? get document => _document;

  String? get id => _id;

  bool get isAttached => _document != null;

  DeltaProvider<V, D> get provider => _subscription.provider;

  void attach(CRDTDocument document, String id) {
    if (_disposed) {
      throw StateError('CrdtEditorBinding.attach called after dispose');
    }
    final point = _subscription.syncTo(
      document,
      id,
      onBeforeAttach: () => _resetWhilePushing = null,
    );
    _document = document;
    _id = id;
    if (point != null) {
      onReset(point.value, ResetCause.initial);
    }
  }

  void detach() {
    _subscription.cancel();
    _document = null;
    _id = null;
    _resetWhilePushing = null;
  }

  void dispose() {
    detach();
    _disposed = true;
  }

  void resync(ResetCause cause) {
    if (_document == null) {
      return;
    }
    _reset(cause);
  }

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

    // Mid-burst the editor misses events the handler already holds. The
    // write lands on a moved base, and marking the stream synced would drop
    // those events: read after the write instead.
    final behind = _subscription.publishedSeq != _subscription.synced;

    _pushing = true;
    try {
      writeToHandler();
    } finally {
      _pushing = false;
    }
    if (_document == null) {
      return;
    }
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
    if (_pushing || event.delta.isEmpty) {
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
    onReset(_subscription.readSynced().value, cause);
  }
}
