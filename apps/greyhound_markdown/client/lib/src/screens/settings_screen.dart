import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:greyhound_markdown_client/src/config.dart';

/// Formats a bundle version as `v<version>` plus the build number when the
/// platform provides one (empty on web / when no `+build` is set).
String formatVersion(PackageInfo info) {
  final build = info.buildNumber;
  return build.isEmpty ? 'v${info.version}' : 'v${info.version} ($build)';
}

/// About / settings page: the expanded version of the footer credits, the app
/// version (resolved cross-platform from the bundle) and access to the
/// open-source licenses.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: Image.asset(kLogoAsset, height: 160),
            ),
            const SizedBox(height: 8),
            Text(
              kAppName,
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Center(child: _VersionLabel()),
            const SizedBox(height: 16),
            Text(
              kAppTagline,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Text('Links', style: theme.textTheme.titleSmall),
            for (final link in kProjectLinks) _LinkTile(link: link),
            const Divider(height: 40),
            Text(
              kCreditLine,
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              kAppLegalese,
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Center(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.description_outlined),
                label: const Text('View licenses'),
                onPressed: () => _showLicenses(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showLicenses(BuildContext context) async {
    final info = await PackageInfo.fromPlatform();
    if (!context.mounted) return;
    showLicensePage(
      context: context,
      applicationName: kAppName,
      applicationVersion: formatVersion(info),
      applicationLegalese: kAppLegalese,
      applicationIcon: Padding(
        padding: const EdgeInsets.all(8),
        child: Image.asset(kLogoAsset, height: 64),
      ),
    );
  }
}

/// The app version, resolved from the platform bundle (web/Android/iOS/…).
class _VersionLabel extends StatelessWidget {
  const _VersionLabel();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        final label = info == null ? '—' : formatVersion(info);
        return Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
        );
      },
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({required this.link});

  final ProjectLink link;

  IconData get _icon => switch (link.url) {
        kRepoUrl => Icons.code,
        kAppSourceUrl => Icons.folder_open,
        _ => Icons.menu_book,
      };

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(_icon),
      title: Text(link.label),
      subtitle: Text(link.url),
      trailing: const Icon(Icons.open_in_new, size: 18),
      onTap: () => launchUrl(
        Uri.parse(link.url),
        mode: LaunchMode.externalApplication,
      ),
    );
  }
}
