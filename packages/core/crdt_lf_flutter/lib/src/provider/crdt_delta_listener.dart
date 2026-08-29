import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/src/provider/_handler_delta_subscription.dart';
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
/// projection you already hold — an `AnimatedList`, a controller, a log —
/// without reading the whole value again.
///
/// It renders [child] unchanged and **never rebuilds the subtree**.
///
/// ## The reset, handled for you
///
/// A delta stream sometimes has to say "read it again" (see `ResetCause`). This
/// widget performs that read, hands the value to [onReset] and drops the events
/// the value already holds, so [onDelta] never reports a change twice.
///
/// [onReset] fires once at the start with `ResetCause.initial`: seed your
/// projection there.
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
    this.origin,
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

  /// What this listener's own writes are tagged with; `null` when it never
  /// writes.
  ///
  /// A write publishes before it has finished, so [onDelta] would move a
  /// projection that already holds the edit. Tag the write with the same object
  /// and the echo is dropped:
  ///
  /// ```dart
  /// CrdtHandlerDeltaListener<List<String>, SequenceDelta<String>>(
  ///   id: 'todos',
  ///   origin: _tag,
  ///   onDelta: (context, event) => _items = event.delta.apply(_items),
  ///   child: TodoList(
  ///     onAdd: (todo) => doc.runInTransaction(
  ///       () => list.insert(0, todo),
  ///       origin: _tag,
  ///     ),
  ///   ),
  /// );
  /// ```
  ///
  /// [onReset] still fires: a reset asks for a read, whoever caused it.
  final Object? origin;

  /// The subtree rendered unchanged below the listener.
  final Widget? child;

  @override
  State<CrdtHandlerDeltaListener<V, D>> createState() =>
      _CrdtHandlerDeltaListenerState<V, D>();
}

class _CrdtHandlerDeltaListenerState<V, D extends ComposableDelta<D>>
    extends State<CrdtHandlerDeltaListener<V, D>> {
  late final HandlerDeltaSubscription<V, D> _subscription =
      HandlerDeltaSubscription<V, D>(
    resolve: (document, id) =>
        resolveDeltaProvider<V, D>(document, id, 'CrdtHandlerDeltaListener'),
    onReset: (point, cause) => widget.onReset?.call(context, point, cause),
    onDelta: (event) => widget.onDelta?.call(context, event),
    isAlive: () => mounted,
    origin: widget.origin,
    // The reset that opens the subscription reaches [onReset] like any other,
    // one microtask after this build. Reading it here instead would run a
    // user callback — one free to call `setState` — inside `build`.
    seed: false,
  );

  @override
  Widget build(BuildContext context) {
    // Covers a new document and a new id alike, which is why there is no
    // `didUpdateWidget`: `build` always runs after one.
    _subscription.syncTo(context.crdtDocument, widget.id);
    return widget.child ?? const SizedBox.shrink();
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
