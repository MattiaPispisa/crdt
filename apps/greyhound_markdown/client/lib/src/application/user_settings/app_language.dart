import 'package:flutter/widgets.dart';

/// The language the app is shown in.
///
/// An enum rather than a nullable `Locale` field, so it mirrors [ThemeMode]:
/// [system] is a real value, which keeps `copyWith` free of a "clear" flag and
/// lets the setting be stored by name.
///
/// Every entry other than [system] must have an ARB file under `lib/l10n/`,
/// or the app falls back to English on it. A test pins that.
enum AppLanguage {
  /// Follow the language of the device.
  system(null, 'System'),

  /// English.
  english(Locale('en'), 'English'),

  /// Spanish.
  spanish(Locale('es'), 'Español'),

  /// French.
  french(Locale('fr'), 'Français'),

  /// German.
  german(Locale('de'), 'Deutsch'),

  /// Italian.
  italian(Locale('it'), 'Italiano'),

  /// Portuguese.
  portuguese(Locale('pt'), 'Português');

  const AppLanguage(this.locale, this.endonym);

  /// The locale to force, or `null` to let the platform choose.
  final Locale? locale;

  /// The name of this language written in itself.
  ///
  /// Not translated, and not read from the ARB files: a language list is
  /// useful exactly when the reader cannot read the current language, so each
  /// entry has to name itself. [system] is the one exception — it is a
  /// behaviour, not a language, so the picker replaces its value with the
  /// translated `languageSystem`.
  final String endonym;
}
