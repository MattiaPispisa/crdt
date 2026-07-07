import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// External links shown on the right of the app bar: the project documentation
/// and the published package on pub.dev.
///
/// The URLs are injected so each example app can point at its own package.
class AppBarLinks extends StatelessWidget {
  /// Creates the app bar external links.
  const AppBarLinks({
    super.key,
    required this.docsUrl,
    required this.pubDevUrl,
    required this.pubTooltip,
  });

  /// Documentation URL.
  final String docsUrl;

  /// pub.dev package URL.
  final String pubDevUrl;

  /// Tooltip for the pub.dev button, e.g. `'crdt_lf on pub.dev'`.
  final String pubTooltip;

  Future<void> _open(String url) {
    return launchUrl(Uri.parse(url), mode: LaunchMode.platformDefault);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.menu_book_outlined),
          tooltip: 'Documentation',
          onPressed: () => _open(docsUrl),
        ),
        IconButton(
          icon: const Icon(Icons.inventory_2_outlined),
          tooltip: pubTooltip,
          onPressed: () => _open(pubDevUrl),
        ),
      ],
    );
  }
}
