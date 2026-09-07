import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:greyhound_markdown_client/src/application/application.dart';
import 'package:greyhound_markdown_client/src/config.dart';
import 'package:greyhound_markdown_client/src/l10n/l10n_extension.dart';
import 'package:greyhound_markdown_client/src/l10n/labels.dart';
import 'package:greyhound_markdown_client/src/widgets/credit_line.dart';

/// Formats a bundle version as `v<version>` plus the build number when the
/// platform provides one (empty on web / when no `+build` is set).
String formatVersion(PackageInfo info) {
  final build = info.buildNumber;
  return build.isEmpty ? 'v${info.version}' : 'v${info.version} ($build)';
}

/// Settings page: the app's preferences, plus the expanded version of the
/// footer credits, the app version (resolved cross-platform from the bundle)
/// and access to the open-source licenses.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings)),
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
              l10n.appTagline,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            Text(l10n.appearance, style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            const _ThemeModeSelector(),
            const SizedBox(height: 32),
            Text(l10n.language, style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            const _LanguageSelector(),
            const SizedBox(height: 32),
            Text(l10n.editorSection, style: theme.textTheme.titleSmall),
            const _EditorOptions(),
            const SizedBox(height: 32),
            Text(l10n.links, style: theme.textTheme.titleSmall),
            for (final link in ProjectLink.values) _LinkTile(link: link),
            const Divider(height: 40),
            const CreditLine(alignment: WrapAlignment.center),
            const SizedBox(height: 4),
            Text(
              kAppLegalese,
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Center(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.history),
                label: Text(l10n.viewChangelog),
                onPressed: () =>
                    Navigator.of(context).pushNamed(kChangelogRoute),
              ),
            ),
            const SizedBox(height: 12),
            Center(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.description_outlined),
                label: Text(l10n.viewLicenses),
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

/// Light / dark / follow the system, persisted with the rest of the user's
/// preferences.
///
/// A [SegmentedButton], like the view switcher in the editor, so the app keeps
/// one idiom for exclusive choices.
class _ThemeModeSelector extends StatelessWidget {
  const _ThemeModeSelector();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<UserSettingsCubit, UserSettingsState>(
      builder: (context, settings) => SegmentedButton<ThemeMode>(
        segments: [
          ButtonSegment(
            value: ThemeMode.light,
            icon: const Icon(Icons.light_mode),
            label: Text(context.l10n.themeLight),
          ),
          ButtonSegment(
            value: ThemeMode.dark,
            icon: const Icon(Icons.dark_mode),
            label: Text(context.l10n.themeDark),
          ),
          ButtonSegment(
            value: ThemeMode.system,
            icon: const Icon(Icons.brightness_auto),
            label: Text(context.l10n.themeSystem),
          ),
        ],
        selected: {settings.themeMode},
        showSelectedIcon: false,
        onSelectionChanged: (selection) =>
            context.read<UserSettingsCubit>().setThemeMode(selection.single),
      ),
    );
  }
}

/// Follow the device language, or force one of the languages the app is
/// translated into.
///
/// A dropdown rather than the [SegmentedButton] the theme mode uses: the list
/// is as long as [AppLanguage.values] and grows with every translation, well
/// past what a row of segments can hold.
///
/// Only "System" is translated. Every real language names itself
/// ([AppLanguage.endonym]), so a reader who landed on a language they cannot
/// read still finds their own in the list.
class _LanguageSelector extends StatelessWidget {
  const _LanguageSelector();

  /// How [language] is offered in the picker.
  String _label(BuildContext context, AppLanguage language) {
    return language == AppLanguage.system
        ? context.l10n.languageSystem
        : language.endonym;
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<UserSettingsCubit, UserSettingsState>(
      builder: (context, settings) => DropdownButton<AppLanguage>(
        value: settings.language,
        isExpanded: true,
        items: [
          for (final language in AppLanguage.values)
            DropdownMenuItem(
              value: language,
              child: Text(_label(context, language)),
            ),
        ],
        onChanged: (language) {
          if (language != null) {
            context.read<UserSettingsCubit>().setLanguage(language);
          }
        },
      ),
    );
  }
}

/// How the source editor looks: line-number gutter and word wrap.
///
/// Both are local view preferences — they never touch the shared document, so
/// two peers of the same room can read it differently.
class _EditorOptions extends StatelessWidget {
  const _EditorOptions();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<UserSettingsCubit, UserSettingsState>(
      builder: (context, settings) => Column(
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.l10n.lineNumbers),
            subtitle: Text(context.l10n.lineNumbersSubtitle),
            value: settings.showLineNumbers,
            onChanged: (value) => context
                .read<UserSettingsCubit>()
                .setShowLineNumbers(value: value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(context.l10n.wordWrap),
            subtitle: Text(context.l10n.wordWrapSubtitle),
            value: settings.wordWrap,
            onChanged: (value) =>
                context.read<UserSettingsCubit>().setWordWrap(value: value),
          ),
        ],
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
        final label = info == null
            ? context.l10n.versionUnknown
            : formatVersion(info);
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

  IconData get _icon => switch (link) {
        ProjectLink.repo => Icons.code,
        ProjectLink.appSource => Icons.folder_open,
        ProjectLink.docs => Icons.menu_book,
      };

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(_icon),
      title: Text(projectLinkLabel(context, link)),
      subtitle: Text(link.url),
      trailing: const Icon(Icons.open_in_new, size: 18),
      onTap: () => launchUrl(
        Uri.parse(link.url),
        mode: LaunchMode.externalApplication,
      ),
    );
  }
}
