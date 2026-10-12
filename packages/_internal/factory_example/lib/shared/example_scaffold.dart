import 'dart:async';

import 'package:crdt_lf_flutter/crdt_lf_flutter.dart' show CrdtProvider;
import 'package:crdt_socket_sync/replica.dart';
import 'package:factory_example/app/example_environment.dart';
import 'package:factory_example/app/example_sync.dart';
import 'package:factory_example/shared/awareness_cursors.dart';
import 'package:factory_example/shared/example_document.dart';
import 'package:factory_example/shared/layout.dart';
import 'package:factory_example/shared/text_cursor_presence.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// One example: what the home page lists, and how its screen is built.
///
/// `S` is the controller of a pane.
class ExampleScreen<S extends ExampleDocument> {
  /// Creates an example descriptor.
  const ExampleScreen({
    required this.name,
    required this.description,
    required this.path,
    required this.documentId,
    required this.createState,
    required this.buildPane,
  });

  /// The display name, also the screen title.
  final String name;

  /// One line on what the example shows.
  final String description;

  /// The route of the screen.
  final String path;

  /// The document every peer opens. A real server has to know it too.
  final String documentId;

  /// Builds the controller of the pane that shows a replica.
  final S Function(CRDTReplica replica) createState;

  /// Builds the content of a pane from its controller.
  final Widget Function(BuildContext context, S state) buildPane;

  /// Builds the screen of this example.
  Widget build(BuildContext context) => ExampleScaffold<S>(screen: this);
}

/// The screen of [screen]: one pane per peer of the `ExampleSync`.
///
/// Opens a replica per peer when it mounts, and closes them when it
/// unmounts. Reads the `ExampleEnvironment` above it.
class ExampleScaffold<S extends ExampleDocument> extends StatefulWidget {
  /// Creates the screen of [screen].
  const ExampleScaffold({required this.screen, super.key});

  /// The example this screen shows.
  final ExampleScreen<S> screen;

  @override
  State<ExampleScaffold<S>> createState() => _ExampleScaffoldState<S>();
}

class _ExampleScaffoldState<S extends ExampleDocument>
    extends State<ExampleScaffold<S>> {
  late final ExampleEnvironment _environment;

  // Owned here, not inside the pane subtree, so they survive the responsive
  // layout swap: an in-pane `ChangeNotifierProvider(create:)` would dispose
  // the controller mid-frame when the breakpoint is crossed.
  List<_Pane<S>>? _panes;
  Object? _error;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _environment = context.read<ExampleEnvironment>();
    unawaited(_open());
  }

  Future<void> _open() async {
    final sync = _environment.sync;
    final documentId = widget.screen.documentId;
    final opening = [
      for (final peer in sync.peers) _environment.open(documentId, peer),
    ];

    final List<CRDTReplica> replicas;
    try {
      replicas = await Future.wait(opening);
    } catch (error) {
      for (final (index, replica) in opening.indexed) {
        unawaited(
          replica.then(
            (replica) =>
                _environment.close(documentId, sync.peers[index], replica),
            onError: (_) {},
          ),
        );
      }
      if (!_disposed) {
        setState(() => _error = error);
      }
      return;
    }

    final panes = [
      for (final (index, replica) in replicas.indexed)
        _Pane<S>(
          peer: sync.peers[index],
          replica: replica,
          presence: sync.textPresence(replica.client!, sync.peers[index]),
          state: widget.screen.createState(replica),
        ),
    ];
    if (_disposed) {
      _close(panes);
      return;
    }
    setState(() => _panes = panes);
  }

  void _close(List<_Pane<S>> panes) {
    for (final pane in panes) {
      pane.state.dispose();
      pane.presence?.dispose();
      _environment.close(widget.screen.documentId, pane.peer, pane.replica);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    final panes = _panes;
    if (panes != null) {
      _close(panes);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.screen.name;
    final actions = [
      _environment.sync.buildSettings(context),
      _environment.links,
    ];
    final panes = _panes;
    if (panes == null) {
      return Scaffold(
        appBar: AppBar(title: Text(title), actions: actions),
        body: Center(
          child:
              _error == null
                  ? const CircularProgressIndicator()
                  : Text('Could not open the example: $_error'),
        ),
      );
    }
    return AppLayout(
      title: title,
      actions: actions,
      panels: [
        for (final pane in panes)
          Panel(label: pane.peer.label, child: _buildPane(pane)),
      ],
    );
  }

  Widget _buildPane(_Pane<S> pane) {
    // Document reactivity comes from the crdt_lf_flutter widgets rooted in
    // CrdtProvider; the controller only signals its own state (time travel,
    // GC). Provided by value: rebuilding across the layout swap never
    // disposes it.
    final content = CrdtProvider.value(
      value: pane.replica.document,
      child: Provider<TextCursorPresence?>.value(
        value: pane.presence,
        child: ChangeNotifierProvider<S>.value(
          value: pane.state,
          child: Consumer<S>(
            builder:
                (context, state, _) => widget.screen.buildPane(context, state),
          ),
        ),
      ),
    );
    final awareness = pane.replica.client?.awareness;
    if (awareness == null) {
      return content;
    }
    return AwarenessCursors(awareness: awareness, child: content);
  }
}

class _Pane<S extends ExampleDocument> {
  _Pane({
    required this.peer,
    required this.replica,
    required this.presence,
    required this.state,
  });

  final ExamplePeer peer;
  final CRDTReplica replica;
  final TextCursorPresence? presence;
  final S state;
}
