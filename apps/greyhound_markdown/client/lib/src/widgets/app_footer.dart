import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:greyhound_markdown_client/src/config.dart';

/// Credits and project links, plus an entry point to the about/settings page.
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
          Text(kCreditLine, style: theme.textTheme.bodySmall),
          for (final link in kProjectLinks)
            _FooterLink(label: link.label, url: link.url, style: linkStyle),
          InkWell(
            onTap: () => Navigator.of(context).pushNamed(kSettingsRoute),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 14,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Text('About', style: linkStyle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FooterLink extends StatelessWidget {
  const _FooterLink({
    required this.label,
    required this.url,
    required this.style,
  });

  final String label;
  final String url;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => launchUrl(Uri.parse(url)),
      child: Text(label, style: style),
    );
  }
}
