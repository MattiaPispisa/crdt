import 'package:flutter/material.dart';
import 'package:shared_examples_infrastructure/shared/document_pane.dart';
import 'package:shared_examples_infrastructure/shared/example_scaffold.dart';

import '_state.dart';
import '_views.dart';

/// Builds the nested Document example screen (built on the reference handlers)
/// from the given [sessionsFactory].
///
/// Sortable chapters, each with sortable paragraphs holding collaborative text
/// and an extensible, sortable list of blocks. Nested CRDTs that merge
/// conflict-free.
Widget documentExample({
  required SessionsFactory sessionsFactory,
  AppBarActionsBuilder? appBarActionsBuilder,
}) {
  return ExampleScaffold<DocumentExampleState>(
    title: 'Document',
    sessionsFactory: sessionsFactory,
    appBarActionsBuilder: appBarActionsBuilder,
    stateBuilder: DocumentExampleState.new,
    paneBuilder:
        (context, state) => DocumentPane(
          state: state,
          onAdd: state.addChapter,
          addDialogTitle: 'Add Chapter',
          body: _ChapterList(state: state),
        ),
  );
}

class _ChapterList extends StatelessWidget {
  const _ChapterList({required this.state});

  final DocumentExampleState state;

  @override
  Widget build(BuildContext context) {
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
  }
}
