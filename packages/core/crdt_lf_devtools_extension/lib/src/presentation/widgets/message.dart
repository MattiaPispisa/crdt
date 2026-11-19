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
