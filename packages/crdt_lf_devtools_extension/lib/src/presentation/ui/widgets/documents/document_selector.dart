import 'package:crdt_lf_devtools_extension/src/application/application.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class DocumentSelector extends StatelessWidget {
  const DocumentSelector({super.key});

  void _onChanged(BuildContext context, int? index) {
    context.read<DocumentsCubit>().select(index);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DocumentsCubit, DocumentsState>(
      builder: (context, state) {
        final documents = state.documents ?? [];
        final selectedDocument = state.selectedDocument;

        return DropdownButton<int>(
          value: selectedDocument?.id,
          hint: const Text('Select a document'),
          onChanged: (index) {
            _onChanged(context, index);
          },
          items:
              documents
                  .map(
                    (e) => DropdownMenuItem<int>(
                      value: e.id,
                      child: Text(e.id.toString()),
                    ),
                  )
                  .toList(),
        );
      },
    );
  }
}
