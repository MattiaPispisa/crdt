import 'package:crdt_lf_devtools_extension/src/application/documents/documents_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class DocumentsReloadButton extends StatelessWidget {
  const DocumentsReloadButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      icon: const Icon(Icons.refresh),
      label: const Text('Refresh'),
      onPressed: () {
        context.read<DocumentsCubit>().load();
      },
    );
  }
}
