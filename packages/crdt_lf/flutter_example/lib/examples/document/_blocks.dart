import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter_example/shared/add_item_dialog.dart';
import 'package:crdt_lf_flutter_example/shared/crdt_text_field.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '_state.dart';

/// The block kinds available in the document example.
///
/// This is the extensibility point of the example: to support a new block kind
/// (a heading, an image, …) add another [BlockSpec] to this list. Nothing else
/// needs to change — the "Add block" menu, the renderer and the CRDT model all
/// derive from these specs, factory-style.
const List<BlockSpec> documentBlockSpecs = [TextBlockSpec(), TodoBlockSpec()];

/// Lookup of [BlockSpec] by its [BlockSpec.kind], used when rendering a block.
final Map<String, BlockSpec> blockSpecByKind = {
  for (final spec in documentBlockSpecs) spec.kind: spec,
};

/// Describes one kind of document block: how to create its CRDT content and
/// how to render it.
///
/// Each block is stored as a `CRDTMapRefHandler` holding a single entry whose
/// key is [kind]; the value is the block's content handler returned by
/// [createContent]. Because the content handler can itself be a container, this
/// convention scales to richer block kinds without changing the model.
abstract class BlockSpec {
  /// Const constructor for subclasses.
  const BlockSpec();

  /// The block kind; also used as the (single) block map key.
  String get kind;

  /// Human label shown in the "Add block" menu.
  String get label;

  /// Icon shown in the "Add block" menu and the block header.
  IconData get icon;

  /// Creates the content handler(s) for a new block on the live document.
  Handler<dynamic> createContent(DocumentState state);

  /// Renders the block body.
  ///
  /// Reads go through [state]'s view handler; writes (only when [interactive])
  /// target the live document.
  Widget buildBody(
    BuildContext context,
    DocumentState state,
    CRDTMapRefHandler block,
    bool interactive,
  );
}

/// A paragraph of collaborative text.
class TextBlockSpec extends BlockSpec {
  /// Creates the text block spec.
  const TextBlockSpec();

  @override
  String get kind => 'text';

  @override
  String get label => 'Text';

  @override
  IconData get icon => Icons.notes;

  @override
  Handler<dynamic> createContent(DocumentState state) => state.newText();

  @override
  Widget buildBody(
    BuildContext context,
    DocumentState state,
    CRDTMapRefHandler block,
    bool interactive,
  ) {
    final text = state.blockContent(block) as CRDTFugueTextHandler?;
    return CrdtTextField(
      key: ValueKey('text-${block.id}'),
      value: text?.value ?? '',
      enabled: interactive && text != null,
      hintText: 'Write something…',
      maxLines: null,
      onChanged: (value) {
        if (text != null) {
          state.editText(text, value);
        }
      },
    );
  }
}

/// A sortable todo list: each item has collaborative text and a `done` flag.
class TodoBlockSpec extends BlockSpec {
  /// Creates the todo block spec.
  const TodoBlockSpec();

  @override
  String get kind => 'todo';

  @override
  String get label => 'Todo list';

  @override
  IconData get icon => Icons.checklist;

  @override
  Handler<dynamic> createContent(DocumentState state) => state.newRefList();

  @override
  Widget buildBody(
    BuildContext context,
    DocumentState state,
    CRDTMapRefHandler block,
    bool interactive,
  ) {
    final list = state.blockContent(block) as CRDTMovableListRefHandler?;
    final todos =
        list == null ? const <CRDTMapRefHandler>[] : state.todosOf(list);
    return _TodoBlockBody(list: list, todos: todos, interactive: interactive);
  }
}

class _TodoBlockBody extends StatelessWidget {
  const _TodoBlockBody({
    required this.list,
    required this.todos,
    required this.interactive,
  });

  final CRDTMovableListRefHandler? list;
  final List<CRDTMapRefHandler> todos;
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final state = context.read<DocumentState>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (todos.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            child: Text('No todos', style: TextStyle(color: Colors.grey)),
          )
        // While time traveling (or with no live list) the list is read-only.
        else if (!interactive || list == null)
          Column(
            children: [
              for (var i = 0; i < todos.length; i++)
                _TodoRow(
                  key: ValueKey('todo-ro-${todos[i].id}'),
                  item: todos[i],
                  index: i,
                  list: list,
                  interactive: false,
                ),
            ],
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: todos.length,
            onReorder: (oldIndex, newIndex) {
              if (newIndex > oldIndex) {
                newIndex -= 1;
              }
              state.reorderTodos(list!, oldIndex, newIndex);
            },
            itemBuilder:
                (context, i) => _TodoRow(
                  key: ValueKey('todo-${todos[i].id}'),
                  item: todos[i],
                  index: i,
                  list: list,
                  interactive: true,
                ),
          ),
        if (interactive && list != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Add todo'),
              onPressed:
                  () => promptText(
                    context,
                    title: 'Add todo',
                    hint: 'Todo text',
                    onAdd: (text) => state.addTodo(list!, text),
                  ),
            ),
          ),
      ],
    );
  }
}

class _TodoRow extends StatelessWidget {
  const _TodoRow({
    super.key,
    required this.item,
    required this.index,
    required this.list,
    required this.interactive,
  });

  final CRDTMapRefHandler item;
  final int index;
  final CRDTMovableListRefHandler? list;
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final state = context.read<DocumentState>();
    final text = state.todoText(item);
    final done = state.todoDone(item);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Checkbox(
            value: done,
            onChanged: interactive ? (_) => state.toggleTodo(item) : null,
          ),
          Expanded(
            child: CrdtTextField(
              key: ValueKey('todo-field-${item.id}'),
              value: text?.value ?? '',
              enabled: interactive && text != null,
              hintText: 'Todo',
              style:
                  done
                      ? const TextStyle(
                        decoration: TextDecoration.lineThrough,
                        color: Colors.grey,
                      )
                      : null,
              onChanged: (value) {
                if (text != null) {
                  state.editTodoText(item, value);
                }
              },
            ),
          ),
          if (interactive && list != null) ...[
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete todo',
              visualDensity: VisualDensity.compact,
              onPressed: () => state.removeTodo(list!, index),
            ),
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.drag_handle),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Shows a one-line text dialog and reports the entered text via [onAdd].
///
/// Shared by the document example to add chapters, paragraphs and todos.
Future<void> promptText(
  BuildContext context, {
  required String title,
  required String hint,
  required void Function(String text) onAdd,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (_) => AddItemDialog(title: title, hint: hint, onAdd: onAdd),
  );
}
