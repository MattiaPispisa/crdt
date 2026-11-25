// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf_devtools_extension/src/application/load_status.dart';
import 'package:devtools_app_shared/ui.dart';
import 'package:flutter/material.dart';

/// A centered line of subtle text, with a retry button when [onRetry] is
/// set.
class PaneMessage extends StatelessWidget {
  const PaneMessage(this.text, {this.onRetry, super.key});

  /// The line shown while the changes of a document load.
  PaneMessage.loadingChanges(LoadProgress? progress, {super.key})
    : text = switch (progress) {
        null => 'Loading changes…',
        (:final loaded, :final total) => 'Loading changes $loaded / $total',
      },
      onRetry = null;

  final String text;

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final retry = onRetry;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(defaultSpacing),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SelectableText(
              text,
              textAlign: TextAlign.center,
              style: Theme.of(context).subtleTextStyle,
            ),
            if (retry != null) ...[
              const SizedBox(height: denseSpacing),
              DevToolsButton(
                icon: Icons.refresh,
                label: 'Retry',
                onPressed: retry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A full-width line on a tinted band, with a retry button when [onRetry]
/// is set.
class MessageBanner extends StatelessWidget {
  const MessageBanner(this.text, {this.onRetry, super.key});

  final String text;

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final retry = onRetry;
    return Container(
      width: double.infinity,
      color: theme.colorScheme.secondaryContainer,
      padding: const EdgeInsets.symmetric(
        horizontal: defaultSpacing,
        vertical: densePadding,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: theme.regularTextStyle.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
          if (retry != null)
            DevToolsButton(
              icon: Icons.refresh,
              label: 'Retry',
              onPressed: retry,
            ),
        ],
      ),
    );
  }
}
