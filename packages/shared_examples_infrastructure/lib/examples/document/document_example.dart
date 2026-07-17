import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart' show CrdtHandlerBuilder;
import 'package:flutter/material.dart';
import 'package:shared_examples_infrastructure/examples/ids.dart';
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
  PaneWrapper? paneWrapper,
}) {
  return ExampleScaffold<DocumentExampleState>(
    title: 'Document',
    sessionsFactory: sessionsFactory,
    appBarActionsBuilder: appBarActionsBuilder,
    paneWrapper: paneWrapper,
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
