// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:flutter/material.dart';

import 'todos.dart';

/// A page that shows the todos of the document above it, with undo.
class TodoPage extends StatefulWidget {
  /// Creates the page of the todos.
  const TodoPage({super.key});

  @override
  State<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends State<TodoPage> {
  // #docregion undo
  late final CRDTUndoManager _undo;

  @override
  void initState() {
    super.initState();
    final document = context.crdtDocument;
    // One undo step per action: no time window merges two of them.
    _undo = CRDTUndoManager(document, captureTimeout: Duration.zero)
      ..track(todosOf(document));
  }

  @override
  void dispose() {
    _undo.dispose();
    super.dispose();
  }
  // #enddocregion undo

  // #docregion list
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Todos'),
        actions: [
          StreamBuilder<void>(
            stream: _undo.changes,
            builder:
                (context, _) => Row(
                  children: [
                    IconButton(
                      tooltip: 'Undo',
                      icon: const Icon(Icons.undo),
                      onPressed: _undo.canUndo ? _undo.undo : null,
                    ),
                    IconButton(
                      tooltip: 'Redo',
                      icon: const Icon(Icons.redo),
                      onPressed: _undo.canRedo ? _undo.redo : null,
                    ),
                  ],
                ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'New todo',
        onPressed:
            () => todosOf(context.crdtDocument).dispatch(const TodoAdded('')),
        child: const Icon(Icons.add),
      ),
      body: CrdtHandlerBuilder<CRDTAggregateHandler<TodoList, TodoEvent>>(
        id: 'todos',
        builder: (context, handler) {
          final todos = handler.value.todos;
          return ReorderableListView(
            // The list gives positions; the event names ids.
            onReorderItem: (from, to) {
              final others = [...todos]..removeAt(from);
              handler.dispatch(
                TodoMoved(
                  todos[from].id,
                  after: to == 0 ? null : others[to - 1].id,
                ),
              );
            },
            children: [
              for (final todo in todos)
                TodoTile(
                  key: ValueKey(todo.id),
                  todo: todo,
                  dispatch: handler.dispatch,
                ),
            ],
          );
        },
      ),
    );
  }

  // #enddocregion list
}

// #docregion tile
/// One todo: a check box, its text and a delete button.
class TodoTile extends StatelessWidget {
  /// Creates the tile of [todo].
  const TodoTile({required this.todo, required this.dispatch, super.key});

  /// The todo to show.
  final Todo todo;

  /// Writes an event to the todo list.
  final ValueChanged<TodoEvent> dispatch;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Checkbox(
        value: todo.done,
        onChanged:
            (done) => dispatch(TodoChecked(todo.id, done: done ?? false)),
      ),
      // The text is one field of the aggregate: an edit replaces it whole, on
      // submit. A new text from another peer builds a new field.
      title: TextFormField(
        key: ValueKey(todo.text),
        initialValue: todo.text,
        decoration: const InputDecoration(hintText: 'What to do'),
        onFieldSubmitted: (text) => dispatch(TodoEdited(todo.id, text)),
      ),
      trailing: IconButton(
        tooltip: 'Delete',
        icon: const Icon(Icons.delete_outline),
        onPressed: () => dispatch(TodoRemoved(todo.id)),
      ),
    );
  }
}

// #enddocregion tile
