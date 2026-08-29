import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/src/provider/_handler_delta_subscription.dart';
import 'package:crdt_lf_flutter/src/provider/crdt_delta_listener.dart';
import 'package:crdt_lf_flutter/src/provider/crdt_handler.dart';
import 'package:crdt_lf_flutter/src/provider/crdt_helper.dart';
import 'package:flutter/widgets.dart';

/// Called with the current value of the handler.
typedef CrdtDeltaWidgetBuilder<V> = Widget Function(
  BuildContext context,
  V value,
);

/// Rebuilds [builder] once per change, with the value **already moved** by
/// what that change did.
///
/// [CrdtHandlerBuilder] answers "did this handler move?" and leaves you to
/// read `handler.value`, which projects the whole document. This one keeps the
/// value itself and advances it by the delta of each change, so a rebuild
/// costs the size of the edit rather than the size of the document. On a long
/// text or a large list that is the difference the delta streams exist for.
///
/// It holds the value, so nothing is read again on a rebuild — and the first
/// frame already shows the document, not an empty placeholder.
///
/// ## Example
///
/// ```dart
/// CrdtHandlerDeltaBuilder<List<String>, SequenceDelta<String>>(
///   id: 'todos',
///   builder: (context, todos) => ListView(
///     children: [for (final todo in todos) Text(todo)],
///   ),
/// );
/// ```
///
/// ## Which one to reach for
///
/// - The value goes on screen → this widget.
/// - The change drives a side effect (an `AnimatedList`, a controller, a log)
///   and the subtree must not rebuild → [CrdtHandlerDeltaListener].
/// - You only need to know *that* something moved → [CrdtHandlerBuilder].
///
/// [V] is the handler's value type and [D] its delta type; the pairs the
/// built-in handlers use are listed in the [CrdtHandlerDeltaListener] docs.
class CrdtHandlerDeltaBuilder<V, D extends ComposableDelta<D>>
    extends StatefulWidget {
  /// Creates a builder over the deltas of the handler [id].
  const CrdtHandlerDeltaBuilder({
    required this.id,
    required this.builder,
    super.key,
  });

  /// The id of the handler to follow (as registered on the document).
  final String id;

  /// Called with the current value, once per change.
  final CrdtDeltaWidgetBuilder<V> builder;

  @override
  State<CrdtHandlerDeltaBuilder<V, D>> createState() =>
      _CrdtHandlerDeltaBuilderState<V, D>();
}

class _CrdtHandlerDeltaBuilderState<V, D extends ComposableDelta<D>>
    extends State<CrdtHandlerDeltaBuilder<V, D>> {
  late final HandlerDeltaSubscription<V, D> _subscription =
      HandlerDeltaSubscription<V, D>(
    resolve: (document, id) =>
        resolveDeltaProvider<V, D>(document, id, 'CrdtHandlerDeltaBuilder'),
    onReset: (point, cause) => setState(() => _value = point.value),
    // The handler says how its own delta moves its own value: the same
    // `SequenceDelta` moves a `String` for a text handler and a `List<T>` for
    // a list one.
    onDelta: (event) => setState(() {
      _value = _subscription.provider.applyDelta(_value, event.delta);
    }),
    isAlive: () => mounted,
    // Read while attaching, so the first frame already shows the document.
    seed: true,
  );

  /// The value on screen. Seeded by a read, then moved by the deltas — never
  /// read back from the handler while the stream keeps up.
  late V _value;

  @override
  Widget build(BuildContext context) {
    // Covers a new document and a new id alike, which is why there is no
    // `didUpdateWidget`: `build` always runs after one.
    final seed = _subscription.syncTo(context.crdtDocument, widget.id);
    if (seed != null) {
      // A plain assignment: this is already a build, so there is nothing to
      // schedule.
      _value = seed.value;
    }
    return widget.builder(context, _value);
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
