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
/// [CrdtHandlerBuilder] answers "did this handler move?" and leaves you to read
/// `handler.value`, which projects the whole document. This one keeps the value
/// and advances it by each delta, so a rebuild costs the size of the edit
/// rather than the size of the document. The first frame already shows the
/// document.
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
    onDelta: (event) {
      // A change with no observable effect still gets its own event, and there
      // is no new value to show. `CrdtHandlerDeltaListener` reports it, because
      // its callback also sees who made the change.
      if (event.delta.isEmpty) {
        return;
      }
      // The handler knows both its value type and its delta type, so it is the
      // one that says how the second moves the first.
      setState(() {
        _value = _subscription.provider.applyDelta(_value, event.delta);
      });
    },
    isAlive: () => mounted,
    // Read while attaching, so the first frame already shows the document.
    seed: true,
  );

  /// The value on screen: seeded by one read, then moved by the deltas.
  late V _value;

  @override
  Widget build(BuildContext context) {
    // Covers a new document and a new id alike, so there is no
    // `didUpdateWidget`: `build` always runs after one.
    final seed = _subscription.syncTo(context.crdtDocument, widget.id);
    if (seed != null) {
      // Plain assignment: this is already a build.
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
