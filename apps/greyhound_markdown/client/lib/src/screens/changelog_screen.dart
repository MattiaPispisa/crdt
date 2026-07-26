import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:greyhound_markdown_client/src/config.dart';

/// Renders the bundled [kChangelogAsset] as markdown so users can review what
/// changed between app versions without leaving the app. Links (e.g. issue
/// references) open in the system browser.
class ChangelogScreen extends StatelessWidget {
  const ChangelogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Changelog')),
      body: SafeArea(
        child: FutureBuilder<String>(
          future: rootBundle.loadString(kChangelogAsset),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(child: Text('Could not load the changelog.'));
            }
            final data = snapshot.data;
            if (data == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return Markdown(
              data: data,
              selectable: true,
              padding: const EdgeInsets.all(16),
              onTapLink: (text, href, title) {
                if (href == null) return;
                launchUrl(
                  Uri.parse(href),
                  mode: LaunchMode.externalApplication,
                );
              },
            );
          },
        ),
      ),
    );
  }
}
