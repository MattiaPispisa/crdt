import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter_example/shared/layout.dart';
import 'package:crdt_lf_flutter_example/shared/network.dart';
import 'package:crdt_lf_flutter_example/todo_list/_add_item_dialog.dart';
import 'package:crdt_lf_flutter_example/todo_list/_state.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '_gc.dart';
import '_history.dart';
import '_info.dart';
import '_todo_item.dart';

final author1 = PeerId.parse('79a716de-176e-4347-ba6e-1d9a2de02e15');
final author2 = PeerId.parse('79a716de-176e-4347-ba6e-1d9a2de02e16');

class TodoList extends StatelessWidget {
  const TodoList({super.key});

  @override
  Widget build(BuildContext context) {
    return AppLayout(
      example: 'Todo List',
      leftBody: ChangeNotifierProvider<DocumentState>(
        create:
            (context) =>
                DocumentState.create(author1, network: context.read<Network>()),
        child: _TodoDocument(author: author1),
      ),
      rightBody: ChangeNotifierProvider<DocumentState>(
        create:
            (context) =>
                DocumentState.create(author2, network: context.read<Network>()),
        child: _TodoDocument(author: author2),
      ),
    );
  }
}

class _TodoDocument extends StatelessWidget {
  const _TodoDocument({super.key, required this.author});

  final PeerId author;

  Future<void> _showAddTodoDialog(BuildContext context) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: true, // Allow dismissing by tapping outside
      builder: (BuildContext dialogContext) {
        return AddItemDialog(
          onAdd: (text) {
            context.read<DocumentState>().addTodo(text);
          },
        );
      },
    );
  }

  Widget _floatingActionButton(BuildContext context) {
    return Consumer<DocumentState>(
      builder: (context, state, child) {
        if (state.isTimeTraveling) {
          return const SizedBox.shrink();
        }

        return FloatingActionButton(
          heroTag: author.toString(),
          onPressed: () => _showAddTodoDialog(context),
          tooltip: 'Add Todo',
          child: const Icon(Icons.add),
        );
      },
    );
  }

  Widget _list(BuildContext context, DocumentState state) {
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

  Widget _historySlider(BuildContext context, DocumentState state) {
    if (!state.isTimeTraveling || state.historySession == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: DocumentHistorySlider(historySession: state.historySession!),
    );
  }

  Widget _bottomActions(BuildContext context, DocumentState state) {
    final isTimeTraveling = state.isTimeTraveling;

    final children = <Widget>[];
    if (isTimeTraveling) {
      children.add(const BackToLiveButton());
    } else {
      children
        ..add(ToDocumentHistoryViewButton(state: state))
        ..add(const GarbageCollectionButton());
    }

    return Align(
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(children: children),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<DocumentState>(
        builder: (context, state, child) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DocumentInfo(state: state),
              Expanded(child: _list(context, state)),
              _historySlider(context, state),
              _bottomActions(context, state),
            ],
          );
        },
      ),
      floatingActionButton: _floatingActionButton(context),
    );
  }
}
