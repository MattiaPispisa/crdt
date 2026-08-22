import 'package:crdt_lf_devtools_extension/src/application/application.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/ui/document_changes/_change_card.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/ui/widgets/layout/data_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// History tab body: cursor slider + timeline of changes, with changes
/// applied up to the current cursor highlighted.
class DocumentHistoryView extends StatelessWidget {
  const DocumentHistoryView({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DocumentHistoryCubit, DocumentHistoryState>(
      builder: (context, state) {
        return AppDataBuilder<List<ChangeDescriptor>>(
          loading: state.loading,
          error: state.error,
          data: state.changes,
          builder: (context, changes) {
            final length = state.length ?? changes.length;
            final cursor = state.cursor ?? length;
            return Column(
              children: [
                _CursorControls(cursor: cursor, length: length),
                const Divider(height: 1),
                Expanded(
                  child:
                      changes.isEmpty
                          ? const Center(child: Text('No changes yet'))
                          : ListView.builder(
                            itemCount: changes.length,
                            itemBuilder:
                                (context, index) => CrdtLfChangeCard(
                                  change: changes[index],
                                  highlighted: index < cursor,
                                ),
                          ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _CursorControls extends StatelessWidget {
  const _CursorControls({required this.cursor, required this.length});

  final int cursor;
  final int length;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<DocumentHistoryCubit>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: 'Previous',
                onPressed: cursor > 0 ? cubit.previous : null,
                icon: const Icon(Icons.skip_previous),
              ),
              IconButton(
                tooltip: 'Next',
                onPressed: cursor < length ? cubit.next : null,
                icon: const Icon(Icons.skip_next),
              ),
              const SizedBox(width: 12),
              Text(
                'Cursor $cursor / $length',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
          if (length > 0)
            Slider(
              value: cursor.toDouble(),
              min: 0,
              max: length.toDouble(),
              divisions: length == 0 ? null : length,
              label: '$cursor',
              onChanged: (v) => cubit.setCursor(v.round()),
            ),
        ],
      ),
    );
  }
}
