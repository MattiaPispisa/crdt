import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter_example/shared/layout.dart';
import 'package:crdt_lf_flutter_example/shared/network.dart';
import 'package:crdt_lf_flutter_example/todo_list/_add_item_dialog.dart';
import 'package:crdt_lf_flutter_example/todo_list/state.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

final author1 = PeerId.parse('79a716de-176e-4347-ba6e-1d9a2de02e15');
final author2 = PeerId.parse('79a716de-176e-4347-ba6e-1d9a2de02e16');

class TodoList extends StatelessWidget {
  const TodoList({super.key});

  @override
  Widget build(BuildContext context) {
    return AppLayout(
      example: 'Todo List',
      leftBody: ChangeNotifierProvider<TodoDocumentState>(
        create:
            (context) => TodoDocumentState.create(
              author1,
              network: context.read<Network>(),
            ),
        child: TodoDocument(author: author1),
      ),
      rightBody: ChangeNotifierProvider<TodoDocumentState>(
        create:
            (context) => TodoDocumentState.create(
              author2,
              network: context.read<Network>(),
            ),
        child: TodoDocument(author: author2),
      ),
    );
  }
}

class TodoDocument extends StatelessWidget {
  const TodoDocument({super.key, required this.author});

  final PeerId author;

  Future<void> _showAddTodoDialog(BuildContext context) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: true, // Allow dismissing by tapping outside
      builder: (BuildContext dialogContext) {
        return AddItemDialog(
          onAdd: (text) {
            context.read<TodoDocumentState>().addTodo(text);
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<TodoDocumentState>(
        builder: (context, state, child) {
          if (state.todos.isEmpty) {
            return const Center(
              child: Text('No todos yet. Add one using the button below!'),
            );
          }
          // Build the list if not empty
          return ListView.builder(
            itemCount: state.todos.length,
            itemBuilder: (context, index) {
              final todoText = state.todos[index];

              return _item(context, todoText, index);
            },
          );
        },
      ),
      floatingActionButton: _fab(context),
    );
  }

  Widget _item(BuildContext context, String todo, int index) {
    return ListTile(
      title: Text(todo),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: 'Delete Todo',
        onPressed: () {
          context.read<TodoDocumentState>().removeTodo(index);
        },
      ),
    );
  }

  Widget _fab(BuildContext context) {
    return FloatingActionButton(
      heroTag: author.toString(),
      onPressed: () => _showAddTodoDialog(context),
      tooltip: 'Add Todo',
      child: const Icon(Icons.add),
    );
  }
}
