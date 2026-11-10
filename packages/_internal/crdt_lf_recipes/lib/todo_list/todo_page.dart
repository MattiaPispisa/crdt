// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:flutter/material.dart';

import 'todos.dart';

/// A page that shows the todos of the document above it.
class TodoPage extends StatelessWidget {
  /// Creates the page of the todos.
  const TodoPage({super.key});

  // #docregion list
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Todos')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'New todo',
        // An action needs no rebuild: read the handler once.
        onPressed:
            () => addTodo(
              context.crdtHandler<CRDTMovableListRefHandler>('todos'),
            ),
        child: const Icon(Icons.add),
      ),
      // `nested`: also rebuild when a todo changes, not only the list.
      body: CrdtHandlerBuilder<CRDTMovableListRefHandler>(
        id: 'todos',
        nested: true,
        builder: (context, todos) {
          return ReorderableListView(
            // `to` is the place after the move, as `move` counts it.
            onReorderItem: todos.move,
            children: [
              // One tile per reference, so a tile index is the list index.
              for (final (index, ref) in todos.childRefs().indexed)
                switch (todos.doc.resolveHandler(ref)) {
                  final CRDTMapRefHandler todo => TodoTile(
                    key: ValueKey(ref.id),
                    todo: todo,
                    onDelete: () => todos.removeChildAt(index),
                  ),
                  // A kind this peer does not know, from a newer peer.
                  _ => ListTile(
                    key: ValueKey(ref.id),
                    title: const Text('Unknown item'),
                  ),
                },
            ],
          );
        },
      ),
    );
  }

  // #enddocregion list
}

// #docregion tile
/// One todo: a check box and a collaborative text field.
class TodoTile extends StatelessWidget {
  /// Creates the tile of [todo].
  const TodoTile({required this.todo, required this.onDelete, super.key});

  /// The todo to show.
  final CRDTMapRefHandler todo;

  /// Deletes the todo.
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Checkbox(
        value: todo.done.value ?? false,
        onChanged: (done) => todo.done.set(done ?? false),
      ),
      title: CrdtTextFieldBuilder(
        id: todo.text.id,
        builder:
            (context, controller) => TextField(
              controller: controller,
              decoration: const InputDecoration(hintText: 'What to do'),
            ),
      ),
      trailing: IconButton(
        tooltip: 'Delete',
        icon: const Icon(Icons.delete_outline),
        onPressed: onDelete,
      ),
    );
  }
}

// #enddocregion tile
