import 'package:flutter/widgets.dart';

/// The language the app is shown in.
///
/// An enum rather than a nullable `Locale` field, so it mirrors [ThemeMode]:
/// [system] is a real value, which keeps `copyWith` free of a "clear" flag and
/// lets the setting be stored by name.
enum AppLanguage {
  /// Follow the language of the device.
  system(null),

  /// English.
  english(Locale('en')),

  /// Italian.
  italian(Locale('it'));

  const AppLanguage(this.locale);

  /// The locale to force, or `null` to let the platform choose.
  final Locale? locale;
}
