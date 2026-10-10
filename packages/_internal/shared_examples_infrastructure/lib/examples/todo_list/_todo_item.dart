import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_examples_infrastructure/examples/todo_list/_state.dart';

/// One row of the todo list: a checkbox, the text and a delete button.
class TodoItem extends StatelessWidget {
  /// Creates the row of [todo], at [index] in the list.
  const TodoItem({
    required this.todo,
    required this.index,
    required this.interactive,
    super.key,
  });

  /// The todo this row shows.
  final Todo todo;

  /// The position of [todo] in the list.
  final int index;

  /// Whether the checkbox and the delete button react to taps.
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Checkbox(
        value: todo.isDone,
        onChanged:
            interactive
                ? (_) {
                  context.read<TodoDocumentState>().toggleTodo(index);
                }
                : null,
      ),
      title: Text(
        todo.text,
        style: TextStyle(
          decoration: todo.isDone ? TextDecoration.lineThrough : null,
        ),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline),
        tooltip: 'Delete Todo',
        onPressed:
            interactive
                ? () {
                  context.read<TodoDocumentState>().removeTodo(index);
                }
                : null,
      ),
    );
  }
}
