import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '_state.dart';

class TodoItem extends StatelessWidget {
  const TodoItem({
    super.key,
    required this.todo,
    required this.index,
    required this.interactive,
  });

  final Todo todo;
  final int index;
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Checkbox(
        value: todo.isDone,
        onChanged:
            interactive
                ? (_) {
                  context.read<DocumentState>().toggleTodo(index);
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
                  context.read<DocumentState>().removeTodo(index);
                }
                : null,
      ),
    );
  }
}
