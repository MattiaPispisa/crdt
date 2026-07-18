import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/src/provider/crdt_builder.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:provider/single_child_widget.dart';

/// Signature for the `create` callback of [CrdtProvider].
typedef CreateCrdtDocument = CRDTDocument Function(BuildContext context);

/// {@template crdt_provider}
/// Provides a [CRDTDocument] to its subtree
///
/// Descendants read the document with [CrdtProvider.of], `context.read`,
/// `context.watch`/`context.select` or the [CrdtBuilder], [CrdtSelector] widgets.
/// Because it registers a listener on [CRDTDocument.updates], provider's
/// `context.watch<CRDTDocument>()` and `context.select<CRDTDocument, S>(...)`
/// rebuild on local and remote changes out of the box.
///
/// There are two ways to provide the document:
///
/// - **Owning mode** — [CrdtProvider.new]: the provider builds the document
///   lazily with `create` and **disposes it** when removed from the tree.
/// - **Value mode** — [CrdtProvider.value]: you already own the document and
///   pass it in; the provider **never** disposes it.
///
/// ## Example
/// ```dart
/// // Owning mode: the provider creates and disposes the document.
/// CrdtProvider(
///   create: (_) => CRDTDocument(),
///   child: const MyApp(),
/// );
///
/// // Value mode: the caller owns the document lifecycle.
/// CrdtProvider.value(
///   value: doc,
///   child: CrdtBuilder(builder: (context, _) => Text(textHandler.value)),
/// );
/// ```
/// {@endtemplate}
class CrdtProvider extends SingleChildStatelessWidget {
  /// Creates a [CRDTDocument] via [create] and provides it to [child].
  ///
  /// The provider **owns** the created document and disposes it when it is
  /// removed from the tree. When [lazy] is `true` (the default) the document is
  /// created on first read.
  ///
  /// {@macro crdt_provider}
  const CrdtProvider({
    required CreateCrdtDocument create,
    super.child,
    this.lazy = true,
    super.key,
  })  : _create = create,
        _value = null;

  /// Provides an already-created [value] to [child].
  ///
  /// The document lifecycle is owned by the caller: this provider never
  /// disposes it.
  ///
  /// {@macro crdt_provider}
  const CrdtProvider.value({
    required CRDTDocument value,
    super.child,
    super.key,
  })  : _value = value,
        _create = null,
        lazy = true;

  final CreateCrdtDocument? _create;
  final CRDTDocument? _value;

  /// Whether the document is created lazily (owning mode only).
  final bool lazy;

  /// The nearest provided [CRDTDocument].
  ///
  /// Pass `listen: true` to rebuild the calling widget on every document
  /// update; the default (`false`) is a one-off read.
  static CRDTDocument of(BuildContext context, {bool listen = false}) {
    return Provider.of<CRDTDocument>(context, listen: listen);
  }

  @override
  Widget buildWithChild(BuildContext context, Widget? child) {
    final value = _value;
    if (value != null) {
      return InheritedProvider<CRDTDocument>.value(
        value: value,
        startListening: _startListening,
        child: child,
      );
    }
    return InheritedProvider<CRDTDocument>(
      create: _create,
      dispose: (_, document) => document.dispose(),
      startListening: _startListening,
      lazy: lazy,
      child: child,
    );
  }

  /// Bridges [CRDTDocument.updates] to provider so that `context.watch` /
  /// `context.select` dependents rebuild on every change.
  static VoidCallback _startListening(
    InheritedContext<CRDTDocument?> element,
    CRDTDocument document,
  ) {
    final subscription =
        document.updates.listen((_) => element.markNeedsNotifyDependents());
    return subscription.cancel;
  }
}
