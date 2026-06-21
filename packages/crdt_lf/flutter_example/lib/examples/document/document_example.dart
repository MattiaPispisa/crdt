import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter_example/shared/document_pane.dart';
import 'package:crdt_lf_flutter_example/shared/layout.dart';
import 'package:crdt_lf_flutter_example/shared/network.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '_state.dart';
import '_views.dart';

final _author1 = PeerId.parse('5b3b2c1a-0001-4000-8000-000000000011');
final _author2 = PeerId.parse('5b3b2c1a-0001-4000-8000-000000000012');

/// A nested collaborative document: sortable chapters, each with sortable
/// paragraphs, each holding collaborative text and a sortable list of items.
///
/// Demonstrates nested CRDTs ("flat storage & references"): every node is a
/// container/leaf handler linked by reference, the tree is reconstructed on a
/// remote peer from the received changes, and concurrent edits at any depth
/// merge conflict-free.
class DocumentExample extends StatelessWidget {
  /// Creates the document example.
  const DocumentExample({super.key});

  Widget _pane(PeerId author) {
    return ChangeNotifierProvider<DocumentState>(
      key: ValueKey(author),
      create:
          (context) =>
              DocumentState(author: author, network: context.read<Network>()),
      child: const _DocumentPane(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppLayout(
      example: 'Document',
      leftBody: _pane(_author1),
      rightBody: _pane(_author2),
    );
  }
}

class _DocumentPane extends StatelessWidget {
  const _DocumentPane();

  @override
  Widget build(BuildContext context) {
    return Consumer<DocumentState>(
      builder: (context, state, _) {
        return DocumentPane(
          state: state,
          onAdd: state.addChapter,
          addDialogTitle: 'Add Chapter',
          body: _ChapterList(state: state),
        );
      },
    );
  }
}

class _ChapterList extends StatelessWidget {
  const _ChapterList({required this.state});

  final DocumentState state;

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
