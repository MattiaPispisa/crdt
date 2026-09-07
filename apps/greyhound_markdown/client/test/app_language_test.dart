import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:greyhound_markdown_client/l10n/gen/app_l10n.dart';
import 'package:greyhound_markdown_client/src/application/application.dart';

void main() {
  group('AppLanguage', () {
    test('offers exactly the locales the app is translated into', () {
      final offered = AppLanguage.values
          .map((language) => language.locale)
          .whereType<Locale>()
          .map((locale) => locale.languageCode)
          .toSet();
      final translated = AppL10n.supportedLocales
          .map((locale) => locale.languageCode)
          .toSet();

      // Both directions: an enum entry with no ARB would silently show
      // English, and an ARB with no enum entry would be unreachable from the
      // picker.
      expect(offered, translated);
    });

    test('names every language in itself', () {
      for (final language in AppLanguage.values) {
        expect(language.endonym, isNotEmpty, reason: language.name);
      }
      expect(
        AppLanguage.values.map((language) => language.endonym).toSet(),
        hasLength(AppLanguage.values.length),
      );
    });

    test('each locale loads its own translations, not the fallback', () async {
      // One word per language, enough to catch an ARB whose `@@locale` does
      // not match its file name — gen-l10n would then quietly serve English.
      const settingsPerLocale = {
        'en': 'Settings',
        'es': 'Ajustes',
        'fr': 'Paramètres',
        'de': 'Einstellungen',
        'it': 'Impostazioni',
        'pt': 'Configurações',
      };

      for (final entry in settingsPerLocale.entries) {
        final l10n = await AppL10n.delegate.load(Locale(entry.key));
        expect(l10n.settings, entry.value, reason: entry.key);
      }
    });
  });
}
