import 'package:flutter/material.dart';

import 'package:greyhound_markdown_client/src/config.dart';
import 'package:greyhound_markdown_client/src/widgets/credit_line.dart';
import 'package:greyhound_markdown_client/src/widgets/footer_link.dart';

/// Credits and project links, plus an entry point to the settings page.
class AppFooter extends StatelessWidget {
  const AppFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final linkStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.primary,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: [
          const CreditLine(),
          for (final link in kProjectLinks)
            FooterLink(label: link.label, url: link.url, style: linkStyle),
          InkWell(
            onTap: () => Navigator.of(context).pushNamed(kSettingsRoute),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.settings_outlined,
                  size: 14,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Text('Settings', style: linkStyle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
