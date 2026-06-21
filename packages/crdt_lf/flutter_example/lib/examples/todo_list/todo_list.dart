import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter_example/shared/document_pane.dart';
import 'package:crdt_lf_flutter_example/shared/layout.dart';
import 'package:crdt_lf_flutter_example/shared/network.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '_state.dart';
import '_todo_item.dart';

final _author1 = PeerId.parse('79a716de-176e-4347-ba6e-1d9a2de02e15');
final _author2 = PeerId.parse('79a716de-176e-4347-ba6e-1d9a2de02e16');

/// A collaborative todo list backed by [CRDTListHandler].
class TodoList extends StatelessWidget {
  /// Creates the todo list example.
  const TodoList({super.key});

  Widget _pane(PeerId author) {
    return ChangeNotifierProvider<DocumentState>(
      key: ValueKey(author),
      create:
          (context) =>
              DocumentState(author: author, network: context.read<Network>()),
      child: const _TodoPane(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppLayout(
      example: 'Todo List',
      leftBody: _pane(_author1),
      rightBody: _pane(_author2),
    );
  }
}

class _TodoPane extends StatelessWidget {
  const _TodoPane();

  @override
  Widget build(BuildContext context) {
    return Consumer<DocumentState>(
      builder: (context, state, _) {
        return DocumentPane(
          state: state,
          onAdd: state.addTodo,
          body: _TodoListView(state: state),
        );
      },
    );
  }
}

class _TodoListView extends StatelessWidget {
  const _TodoListView({required this.state});

  final DocumentState state;

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
