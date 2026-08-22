import 'package:crdt_lf_devtools_extension/src/application/application.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/ui/widgets/layout/data_builder.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class TrackedDocumentsLayout extends StatelessWidget {
  const TrackedDocumentsLayout({super.key, required this.builder});

  final Widget Function(
    BuildContext context,
    List<TrackedDocument> documents,
    TrackedDocument? selectedDocument,
  )
  builder;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DocumentsCubit, DocumentsState>(
      builder: (context, state) {
        return AppDataBuilder<List<TrackedDocument>>(
          data: state.documents,
          error: state.error,
          loading: state.loading,
          builder: (context, documents) {
            return builder(context, documents, state.selectedDocument);
          },
        );
      },
    );
  }
}
