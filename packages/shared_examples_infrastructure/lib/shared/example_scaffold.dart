import 'package:crdt_lf/crdt_lf.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_examples_infrastructure/shared/example_document.dart';
import 'package:shared_examples_infrastructure/shared/example_sync_session.dart';
import 'package:shared_examples_infrastructure/shared/layout.dart';

/// Creates the [ExampleSyncSession]s for one example screen.
///
/// Called once when the screen mounts; the returned sessions are disposed when
/// it unmounts. The crdt_lf example returns two (simulated peers), the socket
/// example returns one (this app instance).
typedef SessionsFactory = List<ExampleSyncSession> Function();

/// Builds the app-bar trailing actions from the live sessions (so an app can,
/// e.g., build a connection indicator from the session's client).
typedef AppBarActionsBuilder =
    List<Widget> Function(List<ExampleSyncSession> sessions);

/// Wraps a pane's content, given its [session], so an app can overlay
/// session-specific chrome on every example (e.g. live awareness cursors).
typedef PaneWrapper = Widget Function(ExampleSyncSession session, Widget child);

/// Shared screen scaffold for an example.
///
/// Owns the session lifecycle (creates them on mount, disposes on unmount),
/// lays one [Panel] per session out via [AppLayout], and wires each panel to a
/// per-session [ExampleDocument] controller `S` through a
/// `ChangeNotifierProvider`. Everything example-specific is injected:
/// [createState] (how to build the typed controller) and [paneBuilder] (the
/// pane body, typically a `DocumentPane`).
class ExampleScaffold<S extends ExampleDocument> extends StatefulWidget {
  /// Creates an example scaffold.
  const ExampleScaffold({
    super.key,
    required this.title,
    required this.sessionsFactory,
    required this.stateBuilder,
    required this.paneBuilder,
    this.appBarActionsBuilder,
    this.paneWrapper,
  });

  /// App-bar title.
  final String title;

  /// Creates the sessions shown by this screen.
  final SessionsFactory sessionsFactory;

  /// Builds the typed controller for a session's document.
  final S Function(CRDTDocument document) stateBuilder;

  /// Builds the pane content for a session's controller.
  final Widget Function(BuildContext context, S state) paneBuilder;

  /// Optional builder for the app-bar trailing actions.
  final AppBarActionsBuilder? appBarActionsBuilder;

  /// Optional wrapper applied to each pane's content (with its session).
  final PaneWrapper? paneWrapper;

  @override
  State<ExampleScaffold<S>> createState() => _ExampleScaffoldState<S>();
}

class _ExampleScaffoldState<S extends ExampleDocument>
    extends State<ExampleScaffold<S>> {
  late final List<ExampleSyncSession> _sessions;

  @override
  void initState() {
    super.initState();
    _sessions = widget.sessionsFactory();
  }

  @override
  void dispose() {
    for (final session in _sessions) {
      session.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppLayout(
      title: widget.title,
      actions: widget.appBarActionsBuilder?.call(_sessions) ?? const [],
      panels: [
        for (final session in _sessions)
          Panel(label: session.label, child: _pane(session)),
      ],
    );
  }

  Widget _pane(ExampleSyncSession session) {
    final content = ChangeNotifierProvider<S>(
      create: (_) => widget.stateBuilder(session.document),
      child: Consumer<S>(
        builder: (context, state, _) => widget.paneBuilder(context, state),
      ),
    );
    return widget.paneWrapper?.call(session, content) ?? content;
  }
}
