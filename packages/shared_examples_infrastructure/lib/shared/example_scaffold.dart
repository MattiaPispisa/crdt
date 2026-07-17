import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart' show CrdtProvider;
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

  /// The per-session controllers, owned here (not inside the pane subtree) so
  /// they survive the responsive desktop/mobile layout swap. If they were
  /// created by an in-pane `ChangeNotifierProvider(create:)`, crossing the
  /// breakpoint would unmount the pane and dispose the controller mid-frame,
  /// leaving `Consumer<S>` reading a disposed (null) provider.
  late final List<S> _states;

  @override
  void initState() {
    super.initState();
    _sessions = widget.sessionsFactory();
    _states = [
      for (final session in _sessions) widget.stateBuilder(session.document),
    ];
  }

  @override
  void dispose() {
    for (final state in _states) {
      state.dispose();
    }
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
        for (var i = 0; i < _sessions.length; i++)
          Panel(
            label: _sessions[i].label,
            child: _pane(_sessions[i], _states[i]),
          ),
      ],
    );
  }

  Widget _pane(ExampleSyncSession session, S state) {
    // Document reactivity comes from the crdt_lf_flutter widgets rooted in
    // CrdtProvider; the ChangeNotifier controller only signals its own state
    // (time travel, GC). The session is exposed (nullable) so the shared
    // fields can reach the optional text-cursor presence channel.
    //
    // The controller is provided by value (owned by this State), so rebuilding
    // this subtree across the layout swap never disposes it.
    final content = CrdtProvider.value(
      value: session.document,
      child: Provider<ExampleSyncSession?>.value(
        value: session,
        child: ChangeNotifierProvider<S>.value(
          value: state,
          child: Consumer<S>(
            builder: (context, state, _) => widget.paneBuilder(context, state),
          ),
        ),
      ),
    );
    return widget.paneWrapper?.call(session, content) ?? content;
  }
}
