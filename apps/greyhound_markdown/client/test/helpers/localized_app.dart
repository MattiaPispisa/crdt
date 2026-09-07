import 'package:flutter/material.dart';

import 'package:greyhound_markdown_client/l10n/gen/app_l10n.dart';

/// A [MaterialApp] that can resolve [AppL10n], with [home] as its page.
///
/// A bare `MaterialApp` carries only the framework delegates, so any widget
/// reading `context.l10n` throws under it. Defaults to English, so assertions
/// on English text keep reading as they did.
Widget localizedApp(
  Widget home, {
  Locale locale = const Locale('en'),
  ThemeData? theme,
}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: AppL10n.localizationsDelegates,
    supportedLocales: AppL10n.supportedLocales,
    theme: theme,
    home: home,
  );
}

/// The English translations, for a test that needs them outside a widget tree.
Future<AppL10n> englishL10n() => AppL10n.delegate.load(const Locale('en'));
