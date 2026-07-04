import 'package:flutter/material.dart';
import 'package:shared_examples_infrastructure/shared/document_pane.dart';
import 'package:shared_examples_infrastructure/shared/example_scaffold.dart';

import '_state.dart';
import '_todo_item.dart';

/// Builds the Todo List example screen (backed by `CRDTListHandler`) from the
/// given [sessionsFactory].
///
/// The crdt_lf app passes two simulated sessions (side-by-side peers); the
/// socket app passes one (this instance is a single real peer).
Widget todoListExample({
  required SessionsFactory sessionsFactory,
  AppBarActionsBuilder? appBarActionsBuilder,
}) {
  return ExampleScaffold<TodoDocumentState>(
    title: 'Todo List',
    sessionsFactory: sessionsFactory,
    appBarActionsBuilder: appBarActionsBuilder,
    stateBuilder: TodoDocumentState.new,
    paneBuilder:
        (context, state) => DocumentPane(
          state: state,
          onAdd: state.addTodo,
          body: _TodoListView(state: state),
        ),
  );
}

class _TodoListView extends StatelessWidget {
  const _TodoListView({required this.state});

  final TodoDocumentState state;

  @override
  Widget build(BuildContext context) {
    final todos = state.todos;
    if (todos.isEmpty) {
      return const Center(
        child: Text('No todos yet. Add one using the button below!'),
      );
    }
    return ListView.builder(
      itemCount: todos.length,
      itemBuilder: (context, index) {
        return TodoItem(
          todo: todos[index],
          index: index,
          interactive: !state.isTimeTraveling,
        );
      },
    );
  }
}
