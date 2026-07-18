import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

const _repoUrl = 'https://github.com/MattiaPispisa/crdt';
const _appSourceUrl =
    'https://github.com/MattiaPispisa/crdt/tree/main/apps/greyhound_markdown';
const _docsUrl = 'https://mattiapispisa.it/crdt/';

/// Credits and project links.
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
          Text(
            'Powered by crdt_lf · created by Mattia Pispisa',
            style: theme.textTheme.bodySmall,
          ),
          _FooterLink(label: 'GitHub', url: _repoUrl, style: linkStyle),
          _FooterLink(
            label: 'App source',
            url: _appSourceUrl,
            style: linkStyle,
          ),
          _FooterLink(label: 'crdt_lf docs', url: _docsUrl, style: linkStyle),
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
