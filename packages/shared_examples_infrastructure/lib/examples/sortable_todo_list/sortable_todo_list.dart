import 'package:flutter/material.dart';
import 'package:shared_examples_infrastructure/shared/document_pane.dart';
import 'package:shared_examples_infrastructure/shared/example_scaffold.dart';

import '_sortable_todo_item.dart';
import '_state.dart';

/// Builds the Sortable Todo List example screen (backed by
/// `CRDTFugueMovableListHandler`) from the given [sessionsFactory].
///
/// Drag the handle to reorder; concurrent moves of the same item converge to a
/// single position instead of duplicating it.
Widget sortableTodoListExample({
  required SessionsFactory sessionsFactory,
  AppBarActionsBuilder? appBarActionsBuilder,
}) {
  return ExampleScaffold<SortableDocumentState>(
    title: 'Sortable Todo List',
    sessionsFactory: sessionsFactory,
    appBarActionsBuilder: appBarActionsBuilder,
    stateBuilder: SortableDocumentState.new,
    paneBuilder:
        (context, state) => DocumentPane(
          state: state,
          onAdd: state.addTodo,
          body: _SortableListView(state: state),
        ),
  );
}

class _SortableListView extends StatelessWidget {
  const _SortableListView({required this.state});

  final SortableDocumentState state;

  @override
  Widget build(BuildContext context) {
    final todos = state.todos;
    if (todos.isEmpty) {
      return const Center(
        child: Text('No todos yet. Add one using the button below!'),
      );
    }

    // While time traveling the list is read-only: render a plain list so the
    // history view cannot be reordered.
    if (state.isTimeTraveling) {
      return ListView.builder(
        itemCount: todos.length,
        itemBuilder:
            (context, index) => SortableTodoItem(
              key: ValueKey('history-$index'),
              todo: todos[index],
              index: index,
              interactive: false,
            ),
      );
    }

    return ReorderableListView.builder(
      itemCount: todos.length,
      // We provide our own drag handle (ReorderableDragStartListener in
      // SortableTodoItem), so disable the automatic ones to avoid two handles.
      buildDefaultDragHandles: false,
      onReorder: (oldIndex, newIndex) {
        // ReorderableListView reports newIndex assuming the item is still in
        // place; convert it to the post-removal destination index expected by
        // the handler's move().
        if (newIndex > oldIndex) {
          newIndex -= 1;
        }
        state.reorder(oldIndex, newIndex);
      },
      itemBuilder:
          (context, index) => SortableTodoItem(
            key: ValueKey(index),
            todo: todos[index],
            index: index,
            interactive: true,
          ),
    );
  }
}
