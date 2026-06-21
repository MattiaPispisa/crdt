import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '_state.dart';

/// A single row of the sortable todo list: checkbox, text, delete and (when
/// interactive) a drag handle to reorder.
class SortableTodoItem extends StatelessWidget {
  /// Creates a sortable todo item.
  const SortableTodoItem({
    super.key,
    required this.todo,
    required this.index,
    required this.interactive,
  });

  /// The todo to render.
  final Todo todo;

  /// The visible index of this item.
  final int index;

  /// Whether the item can be edited (false while time traveling).
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Checkbox(
        value: todo.isDone,
        onChanged:
            interactive
                ? (_) => context.read<SortableDocumentState>().toggleTodo(index)
                : null,
      ),
      title: Text(
        todo.text,
        style: TextStyle(
          decoration: todo.isDone ? TextDecoration.lineThrough : null,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete Todo',
            onPressed:
                interactive
                    ? () =>
                        context.read<SortableDocumentState>().removeTodo(index)
                    : null,
          ),
          if (interactive)
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8.0),
                child: Icon(Icons.drag_handle),
              ),
            ),
        ],
      ),
    );
  }
}
