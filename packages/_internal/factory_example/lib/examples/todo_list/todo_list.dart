import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart' show CrdtHandlerBuilder;
import 'package:factory_example/examples/ids.dart';
import 'package:factory_example/examples/todo_list/_state.dart';
import 'package:factory_example/examples/todo_list/_todo_item.dart';
import 'package:factory_example/shared/document_pane.dart';
import 'package:factory_example/shared/example_scaffold.dart';
import 'package:flutter/material.dart';

/// The Todo List example, backed by `CRDTListHandler`.
final todoListScreen = ExampleScreen<TodoDocumentState>(
  name: 'Todo List',
  description:
      'A collaborative todo list backed by CRDTListHandler. '
      'Concurrent edits merge conflict-free; includes time travel and '
      'garbage collection.',
  path: '/todo-list',
  documentId: ExampleDocumentIds.todoList,
  createState: TodoDocumentState.new,
  buildPane:
      (context, state) => DocumentPane(
        state: state,
        onAdd: state.addTodo,
        body: _TodoListView(state: state),
      ),
);

class _TodoListView extends StatelessWidget {
  const _TodoListView({required this.state});

  final TodoDocumentState state;

  @override
  Widget build(BuildContext context) {
    // Rebuild only when the todo-list handler changes (local or remote);
    // reads still go through `state` so the time-travel view stays correct.
    return CrdtHandlerBuilder<CRDTListHandler<EncodedTodoListType>>(
      id: ExampleHandlerIds.todoList,
      builder: (context, _) {
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
      },
    );
  }
}
