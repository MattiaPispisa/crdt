import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// An inline piece of text that opens [url] in the platform's browser.
class FooterLink extends StatelessWidget {
  /// Creates a link labelled [label] pointing at [url].
  const FooterLink({
    required this.label,
    required this.url,
    this.style,
    super.key,
  });

  /// The visible text.
  final String label;

  /// The address opened on tap.
  final String url;

  /// Overrides the default look: small body text in the primary color.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => launchUrl(Uri.parse(url)),
      child: Text(
        label,
        style:
            style ??
            theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
            ),
      ),
    );
  }
}
