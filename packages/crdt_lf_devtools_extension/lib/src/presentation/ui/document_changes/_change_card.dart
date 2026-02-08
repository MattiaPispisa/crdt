import 'package:crdt_lf_devtools_extension/src/application/application.dart';
import 'package:flutter/material.dart';

/// Compact card for a single CRDT change descriptor.
class CrdtLfChangeCard extends StatelessWidget {
  const CrdtLfChangeCard({
    super.key,
    required this.change,
    this.highlighted = true,
  });

  final ChangeDescriptor change;

  /// When false, the card is dimmed (e.g. for changes after the history
  /// cursor).
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            change.id,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'hlc ${change.hlc} · ${change.payloadSize} B payload · '
            '${change.deps.length} dep${change.deps.length == 1 ? '' : 's'}',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );

    return Opacity(
      opacity: highlighted ? 1 : 0.35,
      child: Card(child: body),
    );
  }
}
