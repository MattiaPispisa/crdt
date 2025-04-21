import 'package:crdt_lf_devtools_extension/src/application/document_changes/document_changes_cubit.dart';
import 'package:crdt_lf_devtools_extension/src/application/documents/documents_cubit.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/extension/context.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/ui/document_changes/_change_card.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/ui/widgets/documents/layout.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/ui/widgets/documents/toolbar.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/ui/widgets/layout/data_builder.dart';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:crdt_lf/crdt_lf.dart' as crdt_lf;

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
                  ? _selectedDocument(context, selectedDocument)
                  : _noSelection(),
            ),
          ],
        );
      },
    );
  }

  Widget _selectedDocument(
    BuildContext context,
    TrackedDocument selectedDocument,
  ) {
    return BlocProvider(
      key: ValueKey(selectedDocument.id),
      create: (_) => DocumentChangesCubit(
        DocumentChangesCubitArgs(
          service: context.vmService,
          document: selectedDocument,
        ),
      ),
      child: BlocBuilder<DocumentChangesCubit, DocumentChangesState>(
        builder: (context, state) {
          return AppDataBuilder<List<crdt_lf.Change>>(
            loading: state.loading,
            error: state.error,
            data: state.changes,
            builder: (context, changes) {
              return ListView.builder(
                itemCount: changes.length,
                itemBuilder: (context, index) {
                  return CrdtLfChangeCard(
                    change: changes[index],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _noSelection() {
    return const Center(
      child: Text('Select a document and handler to visualize'),
    );
  }
}
