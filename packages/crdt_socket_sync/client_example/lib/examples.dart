import 'package:flutter/material.dart';
import 'package:crdt_socket_sync_client_example/connection_indicator.dart';
import 'package:crdt_socket_sync_client_example/socket_sync_session.dart';
import 'package:crdt_socket_sync_client_example/user/_state.dart';
import 'package:provider/provider.dart';
import 'package:shared_examples_infrastructure/shared_examples_infrastructure.dart';

const _docsUrl = 'https://mattiapispisa.github.io/crdt/';
const _pubDevUrl = 'https://pub.dev/packages/crdt_socket_sync';

/// Signature of the shared example screen builders.
typedef _ExampleScreen =
    Widget Function({
      required SessionsFactory sessionsFactory,
      AppBarActionsBuilder? appBarActionsBuilder,
    });

/// Wraps a shared example [screen] with a single real socket session pointed at
/// the document [documentId] on the server URL stored in [UserState].
WidgetBuilder _socket(_ExampleScreen screen, String documentId) {
  return (context) {
    final user = context.read<UserState>();
    return screen(
      sessionsFactory:
          () => [
            SocketSyncSession(
              url: user.url,
              documentId: documentId,
              author: user.userId,
              label: 'This device',
              metadata: {'name': user.username},
            ),
          ],
      appBarActionsBuilder:
          (sessions) => [
            ConnectionIndicator(
              client: (sessions.first as SocketSyncSession).client,
            ),
            const AppBarLinks(
              docsUrl: _docsUrl,
              pubDevUrl: _pubDevUrl,
              pubTooltip: 'crdt_socket_sync on pub.dev',
            ),
          ],
    );
  };
}

/// The single source of truth for the example list: both the home page and the
/// router are derived from it. Each example is the shared screen wired to a
/// real socket session on its own document id.
final kExamples = <Example>[
  Example(
    name: 'Todo List',
    description:
        'A collaborative todo list backed by CRDTListHandler, synced '
        'live over a real WebSocket server. Open this page in another window '
        'to collaborate.',
    path: '/todo-list',
    builder: _socket(todoListExample, ExampleDocumentIds.todoList),
  ),
  Example(
    name: 'Sortable Todo List',
    description:
        'A reorderable todo list backed by '
        'CRDTFugueMovableListHandler, synced over the real backend. Concurrent '
        'moves of the same item converge without duplicating it.',
    path: '/sortable-todo-list',
    builder: _socket(
      sortableTodoListExample,
      ExampleDocumentIds.sortableTodoList,
    ),
  ),
  Example(
    name: 'Document',
    description:
        'A nested document built on the reference handlers, synced '
        'over the real backend: sortable chapters and paragraphs holding '
        'collaborative text and an extensible list of blocks.',
    path: '/document',
    builder: _socket(documentExample, ExampleDocumentIds.document),
  ),
];

/// App bar actions for the home page.
const List<Widget> homeActions = [
  AppBarLinks(
    docsUrl: _docsUrl,
    pubDevUrl: _pubDevUrl,
    pubTooltip: 'crdt_socket_sync on pub.dev',
  ),
];
