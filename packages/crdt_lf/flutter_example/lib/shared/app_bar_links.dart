import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// External links shown on the right of the app bar across every page:
/// the project documentation and the published package on pub.dev.
class AppBarLinks extends StatelessWidget {
  /// Creates the app bar external links.
  const AppBarLinks({super.key});

  static final Uri _docsUrl = Uri.parse(
    'https://mattiapispisa.github.io/crdt/',
  );
  static final Uri _pubDevUrl = Uri.parse('https://pub.dev/packages/crdt_lf');

  Future<void> _open(Uri url) {
    return launchUrl(url, mode: LaunchMode.platformDefault);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.menu_book_outlined),
          tooltip: 'Documentation',
          onPressed: () => _open(_docsUrl),
        ),
        IconButton(
          icon: const Icon(Icons.inventory_2_outlined),
          tooltip: 'crdt_lf on pub.dev',
          onPressed: () => _open(_pubDevUrl),
        ),
      ],
    );
  }
}
