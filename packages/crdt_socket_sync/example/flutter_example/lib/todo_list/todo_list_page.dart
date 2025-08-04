import 'package:flutter/material.dart';
import 'package:flutter_example/todo_list/_add_item.dart';
import 'package:crdt_lf/crdt_lf.dart';
import 'package:flutter_example/todo_list/_animated_cursors.dart';
import 'package:flutter_example/todo_list/_connection_status.dart';
import 'package:flutter_example/todo_list/_users_connected.dart';
import 'package:flutter_example/todo_list/_user_connected_item.dart';
import 'package:flutter_example/user/_state.dart';
import 'package:provider/provider.dart';

import '_state.dart';
import '_todo.dart';

class TodoListPage extends StatelessWidget {
  const TodoListPage({super.key, required this.documentId});

  final PeerId documentId;

  @override
  Widget build(BuildContext context) {
    final user = context.user;

    return ChangeNotifierProvider<TodoListState>(
      create:
          (context) =>
              TodoListState.create(documentId: documentId, user: user)
                ..connect(),
      child: _TodoListContent(
        key: ValueKey('content_$documentId'),
        userId: user.userId,
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
    return Consumer<TodoListState>(
      builder: (context, state, _) {
        final users =
            UsersConnectedBuilder(
              clients: state.awareness.states.values,
              me: state.myAwareness,
            ).build();

        final cursors =
            users.where((user) => !user.isMe && user.position != null).toList();

        return MouseRegion(
          onHover: (event) {
            context.read<TodoListState>().updateCursor(event.position);
          },
          child: Stack(
            children: [
              Scaffold(
                appBar: AppBar(
                  title: const Text("TODO LIST"),
                  actions: [AvatarUsersConnected(users: users)],
                ),
                body: Column(
                  children: [
                    Expanded(child: _todos(context, state)),
                    ConnectionStatusIndicator(state: state),
                  ],
                ),
                floatingActionButton: _fab(context),
              ),
              IgnorePointer(child: AnimatedCursors(users: cursors)),
            ],
          ),
        );
      },
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
        return TodoItem(todo: state.todos[index], index: index);
      },
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
