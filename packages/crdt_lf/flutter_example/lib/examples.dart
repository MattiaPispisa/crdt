import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter_example/shared/network.dart';
import 'package:crdt_lf_flutter_example/shared/network_settings.dart';
import 'package:crdt_lf_flutter_example/shared/text_presence_hub.dart';
import 'package:crdt_lf_flutter_example/simulated_sync_session.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_examples_infrastructure/shared_examples_infrastructure.dart';

const _docsUrl = 'https://mattiapispisa.github.io/crdt/';
const _pubDevUrl = 'https://pub.dev/packages/crdt_lf';

/// Signature of the shared example screen builders.
typedef _ExampleScreen =
    Widget Function({
      required SessionsFactory sessionsFactory,
      AppBarActionsBuilder? appBarActionsBuilder,
    });

// Two distinct peers per example, sharing one in-memory network bus.
final _todoAuthors = [
  PeerId.parse('79a716de-176e-4347-ba6e-1d9a2de02e15'),
  PeerId.parse('79a716de-176e-4347-ba6e-1d9a2de02e16'),
];
final _sortableAuthors = [
  PeerId.parse('5b3b2c1a-0001-4000-8000-000000000001'),
  PeerId.parse('5b3b2c1a-0001-4000-8000-000000000002'),
];
final _documentAuthors = [
  PeerId.parse('5b3b2c1a-0001-4000-8000-000000000011'),
  PeerId.parse('5b3b2c1a-0001-4000-8000-000000000012'),
];

/// App bar actions for the crdt_lf example: the simulated-network settings plus
/// the shared documentation / pub.dev links.
List<Widget> _appBarActions(List<ExampleSyncSession> _) => const [
  NetworkSettings(),
  AppBarLinks(
    docsUrl: _docsUrl,
    pubDevUrl: _pubDevUrl,
    pubTooltip: 'crdt_lf on pub.dev',
  ),
];

/// Wraps a shared example [screen] with two simulated peers over the app's
/// [Network] (read from the widget tree at navigation time).
WidgetBuilder _simulated(_ExampleScreen screen, List<PeerId> authors) {
  return (context) {
    final network = context.read<Network>();
    return screen(
      sessionsFactory: () {
        // In-memory presence bus between the two peers: type in one pane
        // and see the labelled text cursor in the other (the socket example
        // does the same over the awareness plugin).
        final presence = TextPresenceHub();
        return [
          for (final (index, author) in authors.indexed)
            SimulatedSyncSession(
              author: author,
              network: network,
              label: 'Peer ${index + 1}',
              textPresence: presence.register(
                peerId: author.toString(),
                label: 'Peer ${index + 1}',
              ),
            ),
        ];
      },
      appBarActionsBuilder: _appBarActions,
    );
  };
}

/// The single source of truth for the example list: both the home page and the
/// router are derived from it.
final kExamples = <Example>[
  Example(
    name: 'Todo List',
    description:
        'A collaborative todo list backed by CRDTListHandler. '
        'Concurrent edits merge conflict-free; includes time travel and '
        'garbage collection.',
    path: '/todo-list',
    builder: _simulated(todoListExample, _todoAuthors),
  ),
  Example(
    name: 'Sortable Todo List',
    description:
        'A reorderable todo list backed by '
        'CRDTFugueMovableListHandler. Drag to reorder; concurrent moves of the '
        'same item converge without duplicating it.',
    path: '/sortable-todo-list',
    builder: _simulated(sortableTodoListExample, _sortableAuthors),
  ),
  Example(
    name: 'Document',
    description:
        'A nested document built on the reference handlers '
        '(CRDTMapRefHandler / CRDTMovableListRefHandler): sortable chapters, '
        'each with sortable paragraphs holding collaborative text and an '
        'extensible, sortable list of blocks — text and todo lists '
        '(text + done). Nested CRDTs that merge conflict-free.',
    path: '/document',
    builder: _simulated(documentExample, _documentAuthors),
  ),
];

/// App bar actions for the home page (no network settings there).
const List<Widget> homeActions = [
  AppBarLinks(
    docsUrl: _docsUrl,
    pubDevUrl: _pubDevUrl,
    pubTooltip: 'crdt_lf on pub.dev',
  ),
];
