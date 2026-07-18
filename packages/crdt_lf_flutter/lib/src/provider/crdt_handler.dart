import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/src/common/_crdt_guards.dart';
import 'package:crdt_lf_flutter/src/provider/crdt_builder.dart';
import 'package:crdt_lf_flutter/src/provider/crdt_helper.dart';
import 'package:flutter/widgets.dart';

/// Builder invoked by [CrdtHandlerBuilder] with the resolved handler.
typedef CrdtHandlerWidgetBuilder<H extends Handler<dynamic>> = Widget Function(
  BuildContext context,
  H handler,
);

/// Selects a value [R] from a handler [H].
typedef CrdtHandlerSelectorFn<H extends Handler<dynamic>, R> = R Function(
  BuildContext context,
  H handler,
);

/// Builder invoked by [CrdtHandlerSelector] with the selected value.
typedef CrdtHandlerSelectorWidgetBuilder<R> = Widget Function(
  BuildContext context,
  R value,
);

/// Side-effect callback invoked by [CrdtHandlerListener] on a handler change.
typedef CrdtHandlerListenerCallback<H extends Handler<dynamic>> = void Function(
  BuildContext context,
  H handler,
);

/// A per-handler "did it change" signature that consume the handler's
/// [CRDTDocument.revisionForHandler].
///
/// When [nested], the ids **and** revisions of the handler and every
/// descendant reachable through [ContainerHandler.childRefs] are folded
/// into one hash.
int _signatureOf(
  CRDTDocument document,
  String id, {
  required bool nested,
}) {
  if (!nested) {
    return document.revisionForHandler(id);
  }

  final components = <Object>[];
  final visiting = <String>{};
  void visit(String handlerId) {
    if (!visiting.add(handlerId)) {
      return;
    }
    components
      ..add(handlerId)
      ..add(document.revisionForHandler(handlerId));
    final handler = document.registeredHandlers[handlerId];
    if (handler == null) {
      return;
    }
    if (handler is ContainerHandler) {
      for (final ref in (handler as ContainerHandler).childRefs()) {
        visit(ref.id);
      }
    }
  }

  visit(id);
  return Object.hashAll(components);
}

/// Rebuilds [builder] with the handler registered under [id], **only when that
/// handler changes** — a change applied to it (local or remote), a snapshot
/// import, or (when [nested]) a change to a descendant handler.
///
/// Unlike [CrdtBuilder], **unrelated handlers' changes do not rebuild this
/// widget**. It hands you the concrete typed [H] so you can read its `value`
/// (the base `Handler` exposes none).
///
///  **The right tool to render a whole handler
/// value — including list/map handlers whose value is mutated in place, where a
/// value `Selector` would not detect the change.**
///
/// ## Example
/// ```dart
/// CrdtHandlerBuilder<CRDTListHandler<String>>(
///   id: 'todos',
///   builder: (context, handler) => Text('${handler.value.length}'),
/// );
/// ```
class CrdtHandlerBuilder<H extends Handler<dynamic>> extends StatelessWidget {
  /// Creates a widget that rebuilds only when the handler [id] changes.
  const CrdtHandlerBuilder({
    required this.id,
    required this.builder,
    this.nested = false,
    super.key,
  });

  /// The id of the handler to observe (as registered on the document).
  final String id;

  /// Whether a change to a descendant handler also triggers a rebuild.
  final bool nested;

  /// Called with the resolved handler whenever it changes.
  final CrdtHandlerWidgetBuilder<H> builder;

  @override
  Widget build(BuildContext context) {
    assertHandlerGenericIsSet<H>('CrdtHandlerBuilder');
    context.selectCrdtDocument((doc) => _signatureOf(doc, id, nested: nested));
    return builder(context, context.crdtHandler<H>(id));
  }
}

/// Rebuilds [builder] **only when the value selected from the handler [id]
/// changes** (compared with `==`).
///
/// The selector re-runs on every document update and the result is
/// deduplicated, so this naturally scopes rebuilds to the selected slice
/// regardless of which handler changed. **Select a scalar or immutable value**
/// (e.g. `handler.value.length`), not an in-place-mutated collection.
///
/// ## Example
/// ```dart
/// CrdtHandlerSelector<CRDTListHandler<String>, int>(
///   id: 'todos',
///   selector: (context, handler) => handler.value.length,
///   builder: (context, count) => Text('$count todos'),
/// );
/// ```
class CrdtHandlerSelector<H extends Handler<dynamic>, R>
    extends StatelessWidget {
  /// Creates a widget that rebuilds only when `selector` changes.
  const CrdtHandlerSelector({
    required this.id,
    required this.selector,
    required this.builder,
    super.key,
  });

  /// The id of the handler to observe.
  final String id;

  /// Computes the slice of state to watch from the handler.
  final CrdtHandlerSelectorFn<H, R> selector;

  /// Called with the current selected value.
  final CrdtHandlerSelectorWidgetBuilder<R> builder;

  @override
  Widget build(BuildContext context) {
    assertHandlerGenericIsSet<H>('CrdtHandlerSelector');
    final value = context.selectCrdtDocument(
      (document) => selector(context, resolveCrdtHandler<H>(document, id)),
    );
    return builder(context, value);
  }
}

/// Invokes [listener] as a **side effect** (not a rebuild) whenever the handler
/// registered under [id] changes — a change applied to it, a snapshot import,
/// or (when [nested]) a descendant change.
///
/// Use it for navigation, snackbar, etc.
/// **It renders [child] unchanged.**
class CrdtHandlerListener<H extends Handler<dynamic>> extends StatefulWidget {
  /// Creates a listener that fires [listener] on each handler change.
  const CrdtHandlerListener({
    required this.id,
    required this.listener,
    this.nested = false,
    this.child,
    super.key,
  });

  /// The id of the handler to observe.
  final String id;

  /// Whether a change to a descendant handler also fires [listener].
  final bool nested;

  /// Called (post-frame) whenever the handler changes.
  final CrdtHandlerListenerCallback<H> listener;

  /// The subtree rendered unchanged below the listener.
  final Widget? child;

  @override
  State<CrdtHandlerListener<H>> createState() => _CrdtHandlerListenerState<H>();
}

class _CrdtHandlerListenerState<H extends Handler<dynamic>>
    extends State<CrdtHandlerListener<H>> {
  CRDTDocument? _document;
  int? _lastSignature;

  @override
  Widget build(BuildContext context) {
    assertHandlerGenericIsSet<H>('CrdtHandlerListener');
    final document = context.crdtDocument;
    final signature = context.selectCrdtDocument(
      (doc) => _signatureOf(doc, widget.id, nested: widget.nested),
    );

    // Reset (without firing) when the ambient document is swapped; otherwise
    // fire once per signature change.
    if (!identical(document, _document)) {
      _document = document;
      _lastSignature = signature;
    } else if (_lastSignature != signature) {
      _lastSignature = signature;
      final handler = resolveCrdtHandler<H>(document, widget.id);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.listener(context, handler);
        }
      });
    }

    return widget.child ?? const SizedBox.shrink();
  }
}
