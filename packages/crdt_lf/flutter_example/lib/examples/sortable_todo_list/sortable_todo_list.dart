import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter_example/shared/document_pane.dart';
import 'package:crdt_lf_flutter_example/shared/layout.dart';
import 'package:crdt_lf_flutter_example/shared/network.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '_sortable_todo_item.dart';
import '_state.dart';

final _author1 = PeerId.parse('5b3b2c1a-0001-4000-8000-000000000001');
final _author2 = PeerId.parse('5b3b2c1a-0001-4000-8000-000000000002');

/// A reorderable todo list backed by [CRDTFugueMovableListHandler].
///
/// Drag the handle to reorder. Toggle sync off, reorder the same item on both
/// peers, then sync: the item converges to a single position instead of
/// being duplicated.
class SortableTodoList extends StatelessWidget {
  /// Creates the sortable todo list example.
  const SortableTodoList({super.key});

  Widget _pane(PeerId author) {
    return ChangeNotifierProvider<SortableDocumentState>(
      key: ValueKey(author),
      create: (context) => SortableDocumentState(
        author: author,
        network: context.read<Network>(),
      ),
      child: const _SortablePane(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppLayout(
      example: 'Sortable Todo List',
      leftBody: _pane(_author1),
      rightBody: _pane(_author2),
    );
  }
}

class _SortablePane extends StatelessWidget {
  const _SortablePane();

  @override
  Widget build(BuildContext context) {
    return Consumer<SortableDocumentState>(
      builder: (context, state, _) {
        return DocumentPane(
          state: state,
          onAdd: state.addTodo,
          addDialogTitle: 'Add New Todo',
          body: _SortableListView(state: state),
        );
      },
    );
  }
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
        itemBuilder: (context, index) => SortableTodoItem(
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
      itemBuilder: (context, index) => SortableTodoItem(
        key: ValueKey(index),
        todo: todos[index],
        index: index,
        interactive: true,
      ),
    );
  }
}
