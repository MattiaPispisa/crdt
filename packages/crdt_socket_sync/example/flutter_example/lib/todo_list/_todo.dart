import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_example/todo_list/_state.dart';

class TodoItem extends StatelessWidget {
  const TodoItem({
    super.key,
    required this.todo,
    required this.index,
    this.onHover,
  });

  final Todo todo;
  final int index;
  final void Function(bool isHovering)? onHover;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: MouseRegion(
        onEnter: (_) {
          onHover?.call(true);
        },
        onExit: (_) {
          onHover?.call(false);
        },
        child: Checkbox(
          value: todo.isDone,
          onChanged: (_) {
            context.read<TodoListState>().toggleTodo(index);
          },
        ),
      ),
      title: Text(
        todo.text,
        style: TextStyle(
          decoration: todo.isDone ? TextDecoration.lineThrough : null,
        ),
      ),
      trailing: MouseRegion(
        onEnter: (_) {
          onHover?.call(true);
        },
        onExit: (_) {
          onHover?.call(false);
        },
        child: IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Delete Todo',
          onPressed: () {
            context.read<TodoListState>().removeTodo(index);
          },
        ),
      ),
    );
  }
}
