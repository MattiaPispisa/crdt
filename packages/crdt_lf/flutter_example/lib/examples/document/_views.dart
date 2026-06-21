import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter_example/shared/add_item_dialog.dart';
import 'package:crdt_lf_flutter_example/shared/crdt_text_field.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '_state.dart';

Future<void> _promptText(
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

/// Up / down reorder buttons plus a delete button, shared by every level.
class ReorderControls extends StatelessWidget {
  /// Creates reorder controls.
  const ReorderControls({
    super.key,
    required this.interactive,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDelete,
  });

  /// Whether the controls are enabled.
  final bool interactive;

  /// Whether the element can move up.
  final bool canMoveUp;

  /// Whether the element can move down.
  final bool canMoveDown;

  /// Called to move the element up.
  final VoidCallback onMoveUp;

  /// Called to move the element down.
  final VoidCallback onMoveDown;

  /// Called to delete the element.
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_upward),
          tooltip: 'Move up',
          visualDensity: VisualDensity.compact,
          onPressed: interactive && canMoveUp ? onMoveUp : null,
        ),
        IconButton(
          icon: const Icon(Icons.arrow_downward),
          tooltip: 'Move down',
          visualDensity: VisualDensity.compact,
          onPressed: interactive && canMoveDown ? onMoveDown : null,
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Delete',
          visualDensity: VisualDensity.compact,
          onPressed: interactive ? onDelete : null,
        ),
      ],
    );
  }
}

/// A single chapter: editable title, its paragraphs and an add-paragraph
/// action.
class ChapterCard extends StatelessWidget {
  /// Creates a chapter card.
  const ChapterCard({
    super.key,
    required this.chapter,
    required this.index,
    required this.count,
    required this.interactive,
  });

  /// The chapter container handler.
  final CRDTMapRefHandler chapter;

  /// The chapter index among its siblings.
  final int index;

  /// The number of chapters.
  final int count;

  /// Whether the card can be edited.
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final state = context.read<DocumentState>();
    final title = state.chapterTitle(chapter);
    final paragraphs = state.paragraphsOf(chapter);
    final paragraphsList = state.liveParagraphsOf(chapter);

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Chapter ${index + 1}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: CrdtTextField(
                    key: ValueKey('title-${chapter.id}'),
                    value: title?.value ?? '',
                    enabled: interactive && title != null,
                    hintText: 'Chapter title',
                    onChanged: (text) {
                      if (title != null) {
                        state.editText(title, text);
                      }
                    },
                  ),
                ),
                ReorderControls(
                  interactive: interactive,
                  canMoveUp: index > 0,
                  canMoveDown: index < count - 1,
                  onMoveUp: () => state.reorderChapters(index, index - 1),
                  onMoveDown: () => state.reorderChapters(index, index + 1),
                  onDelete: () => state.removeChapter(index),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < paragraphs.length; i++)
              ParagraphCard(
                key: ValueKey('p-${paragraphs[i].id}'),
                paragraph: paragraphs[i],
                parentList: paragraphsList,
                index: i,
                count: paragraphs.length,
                interactive: interactive,
              ),
            if (interactive && paragraphsList != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Add paragraph'),
                  onPressed:
                      () => _promptText(
                        context,
                        title: 'Add paragraph',
                        hint: 'Paragraph text',
                        onAdd:
                            (text) => state.addParagraph(paragraphsList, text),
                      ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A single paragraph: editable text and a sortable list of items.
class ParagraphCard extends StatelessWidget {
  /// Creates a paragraph card.
  const ParagraphCard({
    super.key,
    required this.paragraph,
    required this.parentList,
    required this.index,
    required this.count,
    required this.interactive,
  });

  /// The paragraph container handler.
  final CRDTMapRefHandler paragraph;

  /// The parent paragraphs list handler (live), or `null` while time
  /// traveling.
  final CRDTMovableListRefHandler? parentList;

  /// The paragraph index among its siblings.
  final int index;

  /// The number of paragraphs.
  final int count;

  /// Whether the card can be edited.
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final state = context.read<DocumentState>();
    final text = state.paragraphText(paragraph);
    final items = state.itemsOf(paragraph);
    final itemsList = state.liveItemsOf(paragraph);

    return Container(
      margin: const EdgeInsets.only(left: 8, top: 4, bottom: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: CrdtTextField(
                  key: ValueKey('text-${paragraph.id}'),
                  value: text?.value ?? '',
                  enabled: interactive && text != null,
                  hintText: 'Paragraph text',
                  maxLines: null,
                  onChanged: (value) {
                    if (text != null) {
                      state.editText(text, value);
                    }
                  },
                ),
              ),
              ReorderControls(
                interactive: interactive && parentList != null,
                canMoveUp: index > 0,
                canMoveDown: index < count - 1,
                onMoveUp:
                    () =>
                        state.reorderParagraphs(parentList!, index, index - 1),
                onMoveDown:
                    () =>
                        state.reorderParagraphs(parentList!, index, index + 1),
                onDelete: () => state.removeParagraph(parentList!, index),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _ItemsList(
            items: items,
            itemsList: itemsList,
            interactive: interactive,
          ),
          if (interactive && itemsList != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add item'),
                onPressed:
                    () => _promptText(
                      context,
                      title: 'Add item',
                      hint: 'Item text',
                      onAdd: (text) => state.addItem(itemsList, text),
                    ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ItemsList extends StatelessWidget {
  const _ItemsList({
    required this.items,
    required this.itemsList,
    required this.interactive,
  });

  final List<CRDTFugueTextHandler> items;
  final CRDTMovableListRefHandler? itemsList;
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final state = context.read<DocumentState>();

    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: Text('No items', style: TextStyle(color: Colors.grey)),
      );
    }

    // While time traveling (or with no live list) the list is read-only.
    if (!interactive || itemsList == null) {
      return Column(
        children: [
          for (var i = 0; i < items.length; i++)
            _ItemRow(
              key: ValueKey('item-ro-${items[i].id}'),
              item: items[i],
              index: i,
              itemsList: itemsList,
              interactive: false,
            ),
        ],
      );
    }

    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: items.length,
      onReorder: (oldIndex, newIndex) {
        if (newIndex > oldIndex) {
          newIndex -= 1;
        }
        state.reorderItems(itemsList!, oldIndex, newIndex);
      },
      itemBuilder:
          (context, i) => _ItemRow(
            key: ValueKey('item-${items[i].id}'),
            item: items[i],
            index: i,
            itemsList: itemsList,
            interactive: true,
          ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    super.key,
    required this.item,
    required this.index,
    required this.itemsList,
    required this.interactive,
  });

  final CRDTFugueTextHandler item;
  final int index;
  final CRDTMovableListRefHandler? itemsList;
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final state = context.read<DocumentState>();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          const Icon(Icons.circle, size: 6),
          const SizedBox(width: 8),
          Expanded(
            child: CrdtTextField(
              key: ValueKey('item-field-${item.id}'),
              value: item.value,
              enabled: interactive,
              hintText: 'Item',
              onChanged: (value) => state.editText(item, value),
            ),
          ),
          if (interactive && itemsList != null) ...[
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete item',
              visualDensity: VisualDensity.compact,
              onPressed: () => state.removeItem(itemsList!, index),
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
