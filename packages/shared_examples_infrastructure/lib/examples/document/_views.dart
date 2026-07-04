import 'package:crdt_lf/crdt_lf.dart';
import 'package:shared_examples_infrastructure/shared/crdt_text_field.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '_blocks.dart';
import '_state.dart';

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
    final state = context.read<DocumentExampleState>();
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
                      () => promptText(
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

/// A single paragraph: editable text and an extensible, sortable list of
/// blocks (text / todo list).
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
    final state = context.read<DocumentExampleState>();
    final text = state.paragraphText(paragraph);
    final blocks = state.blocksOf(paragraph);
    final blocksList = state.liveBlocksOf(paragraph);

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
          for (var i = 0; i < blocks.length; i++)
            BlockCard(
              key: ValueKey('block-${blocks[i].id}'),
              block: blocks[i],
              parentList: blocksList,
              index: i,
              count: blocks.length,
              interactive: interactive,
            ),
          if (interactive && blocksList != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add block'),
                onPressed: () => _showAddBlockMenu(context, state, blocksList),
              ),
            ),
        ],
      ),
    );
  }

  void _showAddBlockMenu(
    BuildContext context,
    DocumentExampleState state,
    CRDTMovableListRefHandler blocks,
  ) {
    showModalBottomSheet<void>(
      context: context,
      builder:
          (sheetContext) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(title: Text('Add block')),
                for (final spec in state.blockSpecs)
                  ListTile(
                    leading: Icon(spec.icon),
                    title: Text(spec.label),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      state.addBlock(blocks, spec);
                    },
                  ),
              ],
            ),
          ),
    );
  }
}

/// A single block inside a paragraph: a header (kind icon + label +
/// reorder/delete) and the block body rendered by its [BlockSpec].
class BlockCard extends StatelessWidget {
  /// Creates a block card.
  const BlockCard({
    super.key,
    required this.block,
    required this.parentList,
    required this.index,
    required this.count,
    required this.interactive,
  });

  /// The block container handler.
  final CRDTMapRefHandler block;

  /// The parent blocks list handler (live), or `null` while time traveling.
  final CRDTMovableListRefHandler? parentList;

  /// The block index among its siblings.
  final int index;

  /// The number of blocks.
  final int count;

  /// Whether the block can be edited.
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final state = context.read<DocumentExampleState>();
    final kind = state.blockKind(block);
    final spec = kind == null ? null : blockSpecByKind[kind];

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(spec?.icon ?? Icons.help_outline, size: 16),
              const SizedBox(width: 6),
              Text(
                spec?.label ?? kind ?? 'Unknown',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const Spacer(),
              ReorderControls(
                interactive: interactive && parentList != null,
                canMoveUp: index > 0,
                canMoveDown: index < count - 1,
                onMoveUp:
                    () => state.reorderBlocks(parentList!, index, index - 1),
                onMoveDown:
                    () => state.reorderBlocks(parentList!, index, index + 1),
                onDelete: () => state.removeBlock(parentList!, index),
              ),
            ],
          ),
          if (spec != null)
            spec.buildBody(context, state, block, interactive)
          else
            const Text(
              'Unsupported block',
              style: TextStyle(color: Colors.grey),
            ),
        ],
      ),
    );
  }
}
