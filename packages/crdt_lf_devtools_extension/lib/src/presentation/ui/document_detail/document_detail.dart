import 'package:crdt_lf_devtools_extension/src/application/application.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/ui/widgets/layout/data_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// State tab body: document metadata + registered handlers and their values.
class DocumentDetailView extends StatelessWidget {
  const DocumentDetailView({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DocumentDetailCubit, DocumentDetailState>(
      builder: (context, state) {
        return AppDataBuilder<TrackedDocument>(
          loading: state.loading,
          error: state.error,
          data: state.document,
          builder: (context, document) {
            final handlers = state.handlers ?? const <HandlerSummary>[];
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _DocumentMetadataCard(document: document),
                const SizedBox(height: 16),
                Text(
                  'Handlers (${handlers.length})',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (handlers.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('No handlers registered'),
                  )
                else
                  ...handlers.map((h) => _HandlerCard(handler: h)),
              ],
            );
          },
        );
      },
    );
  }
}

class _DocumentMetadataCard extends StatelessWidget {
  const _DocumentMetadataCard({required this.document});

  final TrackedDocument document;

  @override
  Widget build(BuildContext context) {
    final mono = TextStyle(
      fontFamily: 'monospace',
      color: Theme.of(context).colorScheme.onSurface,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Document #${document.id}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            _KeyValue(
              label: 'documentId',
              value: document.documentId,
              style: mono,
            ),
            _KeyValue(label: 'peerId', value: document.peerId, style: mono),
            _KeyValue(
              label: 'changes',
              value: document.changesCount.toString(),
            ),
            _KeyValue(
              label: 'handlers',
              value: document.handlersCount.toString(),
            ),
            _KeyValue(
              label: 'version',
              value:
                  document.version.isEmpty
                      ? '<empty>'
                      : document.version.join('\n'),
              style: mono,
            ),
          ],
        ),
      ),
    );
  }
}

class _HandlerCard extends StatelessWidget {
  const _HandlerCard({required this.handler});

  final HandlerSummary handler;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        title: Text(
          handler.id,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(handler.type),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SelectableText(
              handler.value,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }
}

class _KeyValue extends StatelessWidget {
  const _KeyValue({required this.label, required this.value, this.style});

  final String label;
  final String value;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: Theme.of(context).textTheme.labelMedium),
          ),
          Expanded(child: SelectableText(value, style: style)),
        ],
      ),
    );
  }
}
