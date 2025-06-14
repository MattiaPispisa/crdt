import 'package:crdt_socket_sync/client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_example/todo_list/_add_item.dart';
import 'package:crdt_lf/crdt_lf.dart';
import 'package:flutter_example/_user.dart';
import 'package:flutter_example/todo_list/_connection_status.dart';
import 'package:flutter_example/todo_list/_users_connected.dart';
import 'package:provider/provider.dart';

import '_state.dart';

class TodoList extends StatelessWidget {
  const TodoList({super.key, required this.documentId});

  final PeerId documentId;

  @override
  Widget build(BuildContext context) {
    final userId = context.user;
    return ChangeNotifierProvider<TodoListState>(
      create:
          (context) =>
              TodoListState.create(documentId: documentId, userId: userId)
                ..connect(),
      child: _TodoListContent(
        key: ValueKey('content_$documentId'),

        userId: userId,
        documentId: documentId,
      ),
    );
  }
}

class _TodoListContent extends StatelessWidget {
  const _TodoListContent({
    super.key,
    required this.documentId,
    required this.userId,
  });

  final PeerId userId;
  final PeerId documentId;

  Future<void> _showAddTodoDialog(BuildContext context) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: true, // Allow dismissing by tapping outside
      builder: (BuildContext dialogContext) {
        return AddItemDialog(
          onAdd: (text) {
            context.read<TodoListState>().addTodo(text);
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("TODO LIST"),
        actions: [
          UsersConnected(users: [userId]),
        ],
      ),
      body: Consumer<TodoListState>(
        builder: (context, state, child) {
          return Column(
            children: [
              Expanded(child: _todos(context, state)),
              ConnectionStatusIndicator(state: state),
            ],
          );
        },
      ),
      floatingActionButton: _fab(context),
    );
  }

  Widget _todos(BuildContext context, TodoListState state) {
    if (state.todos.isEmpty) {
      return const Center(
        child: Text('No todos yet. Add one using the button below!'),
      );
    }

    return ListView.builder(
      itemCount: state.todos.length,
      itemBuilder: (context, index) {
        final todoText = state.todos[index];

        return _item(context, todoText, index);
      },
    );
  }

  Widget _item(BuildContext context, String todo, int index) {
    return ListTile(
      title: Text(todo),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: 'Delete Todo',
        onPressed: () {
          context.read<TodoListState>().removeTodo(index);
        },
      ),
    );
  }

  Widget _fab(BuildContext context) {
    return FloatingActionButton(
      heroTag: documentId.toString(),
      onPressed: () => _showAddTodoDialog(context),
      tooltip: 'Add Todo',
      child: const Icon(Icons.add),
    );
  }
}
