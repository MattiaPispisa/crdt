import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_example/todo_list/_state.dart';

class TodoItem extends StatelessWidget {
  const TodoItem({super.key, required this.todo, required this.index});

  final Todo todo;
  final int index;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Checkbox(
        value: todo.isDone,
        onChanged: (_) {
          context.read<TodoListState>().toggleTodo(index);
        },
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
        onPressed: () {
          context.read<TodoListState>().removeTodo(index);
        },
      ),
    );
  }
}
