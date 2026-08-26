import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/src/provider/crdt_handler.dart';
import 'package:crdt_lf_flutter/src/provider/crdt_helper.dart';
import 'package:flutter/widgets.dart';

/// Called with what one change did to the handler.
typedef CrdtDeltaCallback<D> = void Function(
  BuildContext context,
  HandlerDelta<D> event,
);

/// Called when the handler's value has to be adopted again from scratch.
typedef CrdtDeltaResetCallback<V> = void Function(
  BuildContext context,
  DeltaSyncPoint<V> sync,
  ResetCause cause,
);

/// Invokes [onDelta] with **what** changed in the handler registered under
/// [id], one call per change, as a side effect.
///
/// [CrdtHandlerListener] tells you *that* a handler changed and hands you the
/// handler to re-read. This one hands you the change itself, so you can move a
/// projection you already hold — drive an `AnimatedList`, replay an edit into a
/// controller, append to a log — without reading the whole value again.
///
/// It renders [child] unchanged and **never rebuilds the subtree**.
///
/// ## The reset, handled for you
///
/// A delta stream sometimes has to say "read it again": a snapshot replaced the
/// base, or the handler dropped the cached state the deltas described (see
/// `ResetCause`). This widget performs that read, hands the value to [onReset],
/// and drops the events the value already holds — so [onDelta] never reports a
/// change twice, and never one the value has already absorbed.
///
/// [onReset] fires once when the subscription starts, with
/// `ResetCause.initial`. Seed your projection there.
///
/// ## Example
///
/// ```dart
/// CrdtHandlerDeltaListener<List<String>, SequenceDelta<String>>(
///   id: 'todos',
///   onReset: (context, sync, cause) => _items = [...sync.value],
///   onDelta: (context, event) => _items = event.delta.apply(_items),
///   child: const TodoList(),
/// );
/// ```
///
/// [V] is the handler's value type and [D] its delta type. The pairs the
/// built-in handlers use:
///
/// | Handler | [V] | [D] |
/// |---|---|---|
/// | the two text handlers | `String` | `SequenceDelta<String>` |
/// | the three list handlers | `List<T>` | `SequenceDelta<T>` |
/// | `CRDTMapHandler<T>` | `Map<String, T>` | `MapDelta<String, T>` |
/// | `CRDTORMapHandler<K, V>` | `Map<K, V>` | `MapDelta<K, V>` |
/// | `CRDTORSetHandler<T>` | `Set<T>` | `SetDelta<T>` |
/// | `CRDTRegisterHandler<T>` | `T?` | `RegisterDelta<T>` |
class CrdtHandlerDeltaListener<V, D extends ComposableDelta<D>>
    extends StatefulWidget {
  /// Creates a listener over the deltas of the handler [id].
  const CrdtHandlerDeltaListener({
    required this.id,
    this.onDelta,
    this.onReset,
    this.child,
    super.key,
  });

  /// The id of the handler to observe (as registered on the document).
  final String id;

  /// Called once per change, with what that change did.
  final CrdtDeltaCallback<D>? onDelta;

  /// Called when the value has to be adopted again, with the value already
  /// read.
  final CrdtDeltaResetCallback<V>? onReset;

  /// The subtree rendered unchanged below the listener.
  final Widget? child;

  @override
  State<CrdtHandlerDeltaListener<V, D>> createState() =>
      _CrdtHandlerDeltaListenerState<V, D>();
}

class _CrdtHandlerDeltaListenerState<V, D extends ComposableDelta<D>>
    extends State<CrdtHandlerDeltaListener<V, D>> {
  CRDTDocument? _document;
  StreamSubscription<HandlerUpdate<D>>? _subscription;

  /// The last point the value was read at. Everything up to it is already
  /// inside what [CrdtHandlerDeltaListener.onReset] handed over.
  int _synced = -1;

  @override
  Widget build(BuildContext context) {
    final document = context.crdtDocument;
    if (!identical(document, _document)) {
      _attach(document);
    }
    return widget.child ?? const SizedBox.shrink();
  }

  @override
  void didUpdateWidget(covariant CrdtHandlerDeltaListener<V, D> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id && _document != null) {
      _attach(_document!);
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  DeltaProvider<V, D> _provider(CRDTDocument document) {
    final handler = document.registeredHandlers[widget.id];
    if (handler != null && handler is DeltaProvider<V, D>) {
      // `Handler` is a base class and `DeltaProvider` a base mixin, so the
      // analyzer will not promote across them. The check above is the proof.
      return handler as DeltaProvider<V, D>;
    }
    throw FlutterError(
      'CrdtHandlerDeltaListener<$V, $D> expected the handler registered under '
      'id "${widget.id}" to publish deltas of that shape, but found '
      '${handler ?? 'none'}.\n'
      'Check the value/delta pair of the handler you meant to observe; the '
      'table in the CrdtHandlerDeltaListener docs lists them.',
    );
  }

  void _attach(CRDTDocument document) {
    unawaited(_subscription?.cancel());
    _document = document;
    _synced = -1;
    _subscription = _provider(document).watch().listen(_onUpdate);
  }

  void _onUpdate(HandlerUpdate<D> update) {
    if (!mounted) {
      return;
    }
    switch (update) {
      case HandlerReset<D>():
        // Reading the value and learning where it sits in the stream is one
        // operation, so nothing can land in between and be applied twice.
        final point = _provider(_document!).readSynced();
        _synced = point.seq;
        widget.onReset?.call(context, point, update.cause);
      case HandlerDelta<D>():
        if (update.seq <= _synced) {
          // Already inside the value the last read handed over.
          return;
        }
        _synced = update.seq;
        widget.onDelta?.call(context, update);
    }
  }
}
