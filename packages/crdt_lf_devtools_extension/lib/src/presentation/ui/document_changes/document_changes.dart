import 'package:crdt_lf_devtools_extension/src/application/application.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/extension/context.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/ui/document_changes/_change_card.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/ui/document_detail/document_detail.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/ui/document_history/document_history.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/ui/widgets/documents/layout.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/ui/widgets/documents/toolbar.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/ui/widgets/layout/data_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Main panel for the selected document.
///
/// Hosts three tabs:
/// - Changes: raw change descriptors as they were applied.
/// - State: live handler list + values.
/// - History: timeline cursor highlighting which changes are "applied".
class DocumentChangesWidget extends StatelessWidget {
  const DocumentChangesWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return TrackedDocumentsLayout(
      builder: (context, documents, selectedDocument) {
        return Column(
          children: [
            const DocumentsToolbar(),
            Expanded(
              child: selectedDocument != null
                  ? _SelectedDocumentTabs(
                      key: ValueKey(selectedDocument.id),
                      document: selectedDocument,
                    )
                  : const _NoSelection(),
            ),
          ],
        );
      },
    );
  }
}

class _SelectedDocumentTabs extends StatelessWidget {
  const _SelectedDocumentTabs({super.key, required this.document});

  final TrackedDocument document;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.list_alt), text: 'Changes'),
              Tab(icon: Icon(Icons.account_tree), text: 'State'),
              Tab(icon: Icon(Icons.history), text: 'History'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _ChangesTab(document: document),
                _StateTab(document: document),
                _HistoryTab(document: document),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChangesTab extends StatelessWidget {
  const _ChangesTab({required this.document});

  final TrackedDocument document;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => DocumentChangesCubit(
        DocumentChangesCubitArgs(
          service: context.vmService,
          document: document,
        ),
      ),
      child: BlocBuilder<DocumentChangesCubit, DocumentChangesState>(
        builder: (context, state) {
          return AppDataBuilder<List<ChangeDescriptor>>(
            loading: state.loading,
            error: state.error,
            data: state.changes,
            builder: (context, changes) {
              if (changes.isEmpty) {
                return const Center(child: Text('No changes yet'));
              }
              return ListView.builder(
                itemCount: changes.length,
                itemBuilder: (context, index) =>
                    CrdtLfChangeCard(change: changes[index]),
              );
            },
          );
        },
      ),
    );
  }
}

class _StateTab extends StatelessWidget {
  const _StateTab({required this.document});

  final TrackedDocument document;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => DocumentDetailCubit(
        DocumentDetailCubitArgs(
          service: context.vmService,
          document: document,
        ),
      ),
      child: const DocumentDetailView(),
    );
  }
}

class _HistoryTab extends StatelessWidget {
  const _HistoryTab({required this.document});

  final TrackedDocument document;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => DocumentHistoryCubit(
        DocumentHistoryCubitArgs(
          service: context.vmService,
          document: document,
        ),
      ),
      child: const DocumentHistoryView(),
    );
  }
}

class _NoSelection extends StatelessWidget {
  const _NoSelection();

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('Select a document to inspect it'));
  }
}
