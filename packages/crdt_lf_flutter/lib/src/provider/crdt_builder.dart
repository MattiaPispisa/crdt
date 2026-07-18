import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/src/provider/crdt_helper.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

/// Builder invoked by [CrdtBuilder] on every document update.
typedef CrdtWidgetBuilder = Widget Function(
  BuildContext context,
  CRDTDocument document,
);

/// Selects a value [R] from the ambient [CRDTDocument].
typedef CrdtDocumentSelector<R> = R Function(
  BuildContext context,
  CRDTDocument document,
);

/// Builder invoked by [CrdtSelector] with the selected value.
typedef CrdtSelectorWidgetBuilder<R> = Widget Function(
  BuildContext context,
  R value,
);

/// Rebuilds [builder] on **every** update of the ambient [CRDTDocument] — local
/// edits, applied remote changes and snapshot imports.
///
/// A thin wrapper over `context.watchCrdtDocument()`: it depends on the
/// document exposed by an ancestor `CrdtProvider`, which notifies on every
/// change (through the `updates` bridge installed by `CrdtProvider`). Read any
/// handler's `value` inside [builder]; the cache-backed getters make it cheap.
///
/// - For rebuilds scoped to a **single handler** use [CrdtHandlerBuilder];
/// for a derived slice use [CrdtSelector].
///
/// ## Example
/// ```dart
/// CrdtBuilder(
///   builder: (context, document) => Text(textHandler.value),
/// );
/// ```
class CrdtBuilder extends StatelessWidget {
  /// Creates a widget that rebuilds on every document update.
  const CrdtBuilder({required this.builder, super.key});

  /// Called on every document update with the ambient document.
  final CrdtWidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    return builder(context, context.watchCrdtDocument());
  }
}

/// Rebuilds [builder] **only when the value returned by [selector] changes**
/// (compared with `==`).
///
/// A thin wrapper over provider's `context.select` on the ambient
/// [CRDTDocument]: derive a small, comparable slice of state (a scalar or
/// immutable value) and skip rebuilds when it is unchanged.
///
/// Remember that the `compar` operator is for ==,
/// and **some handlers, for efficiency, mutate objects**,
/// so they may change while remaining the same by reference.
/// **It's always better to derive a value** (e.g. `handler.value.length`)
/// rather than use the raw collection.
///
/// For whole-collection rebuilds use [CrdtBuilder].
///
/// ## Example
/// ```dart
/// CrdtSelector<int>(
///   selector: (context, document) => listHandler.value.length,
///   builder: (context, count) => Text('$count todos'),
/// );
/// ```
class CrdtSelector<R> extends StatelessWidget {
  /// Creates a widget that rebuilds only when `selector` changes.
  const CrdtSelector({
    required this.selector,
    required this.builder,
    super.key,
  });

  /// Computes the slice of state to watch.
  final CrdtDocumentSelector<R> selector;

  /// Called with the current selected value.
  final CrdtSelectorWidgetBuilder<R> builder;

  @override
  Widget build(BuildContext context) {
    final value = context.select<CRDTDocument, R>(
      (document) => selector(context, document),
    );
    return builder(context, value);
  }
}
