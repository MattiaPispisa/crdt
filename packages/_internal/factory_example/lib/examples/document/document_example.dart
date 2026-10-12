import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart' show CrdtHandlerBuilder;
import 'package:factory_example/examples/document/_state.dart';
import 'package:factory_example/examples/document/_views.dart';
import 'package:factory_example/examples/ids.dart';
import 'package:factory_example/shared/document_pane.dart';
import 'package:factory_example/shared/example_scaffold.dart';
import 'package:flutter/material.dart';

/// The Document example, built on the reference handlers.
final documentScreen = ExampleScreen<DocumentExampleState>(
  name: 'Document',
  description:
      'A nested document built on the reference handlers '
      '(CRDTMapRefHandler / CRDTMovableListRefHandler): sortable chapters, '
      'each with sortable paragraphs holding collaborative text and an '
      'extensible, sortable list of blocks — text and todo lists '
      '(text + done). Nested CRDTs that merge conflict-free.',
  path: '/document',
  documentId: ExampleDocumentIds.document,
  createState: DocumentExampleState.new,
  buildPane:
      (context, state) => DocumentPane(
        state: state,
        onAdd: state.addChapter,
        addDialogTitle: 'Add Chapter',
        body: _ChapterList(state: state),
      ),
);

class _ChapterList extends StatelessWidget {
  const _ChapterList({required this.state});

  final DocumentExampleState state;

  @override
  Widget build(BuildContext context) {
    // Rebuild when the chapters root — or any nested handler of the tree
    // (titles, paragraphs, blocks, todos) — changes; reads still go through
    // `state` so the time-travel view stays correct. Note that the text
    // fields themselves never rebuild: `CrdtTextField` binds its controller
    // directly (see `CrdtTextFieldBuilder`).
    return CrdtHandlerBuilder<CRDTMovableListRefHandler>(
      id: ExampleHandlerIds.document,
      nested: true,
      builder: (context, _) {
        final chapters = state.chapters;
        if (chapters.isEmpty) {
          return const Center(
            child: Text('No chapters yet. Add one using the button below!'),
          );
        }

        final interactive = !state.isTimeTraveling;
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          itemCount: chapters.length,
          itemBuilder:
              (context, index) => ChapterCard(
                key: ValueKey('c-${chapters[index].id}'),
                chapter: chapters[index],
                index: index,
                count: chapters.length,
                interactive: interactive,
              ),
        );
      },
    );
  }
}
