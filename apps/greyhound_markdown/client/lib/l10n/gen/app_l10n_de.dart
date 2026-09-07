// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_l10n.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppL10nDe extends AppL10n {
  AppL10nDe([String locale = 'de']) : super(locale);

  @override
  String get settings => 'Einstellungen';

  @override
  String get appearance => 'Darstellung';

  @override
  String get language => 'Sprache';

  @override
  String get editorSection => 'Editor';

  @override
  String get links => 'Links';

  @override
  String get themeLight => 'Hell';

  @override
  String get themeDark => 'Dunkel';

  @override
  String get themeSystem => 'System';

  @override
  String get languageSystem => 'System';

  @override
  String get lineNumbers => 'Zeilennummern';

  @override
  String get lineNumbersSubtitle => 'Zeigt Zeilennummern neben dem Quelltext';

  @override
  String get wordWrap => 'Zeilenumbruch';

  @override
  String get wordWrapSubtitle =>
      'Bricht lange Zeilen um, statt horizontal zu scrollen';

  @override
  String get viewChangelog => 'Changelog ansehen';

  @override
  String get viewLicenses => 'Lizenzen ansehen';

  @override
  String get versionUnknown => '—';

  @override
  String get appTagline =>
      'Ein kollaborativer Markdown-Editor in Echtzeit, gebaut auf crdt_lf.';

  @override
  String get creditPrefix => 'Powered by crdt_lf · erstellt von ';

  @override
  String get linkRepo => 'GitHub';

  @override
  String get linkAppSource => 'Quellcode der App';

  @override
  String get linkDocs => 'crdt_lf-Dokumentation';

  @override
  String get yourName => 'Dein Name';

  @override
  String get createRoom => 'Neuen Raum erstellen';

  @override
  String get join => 'Beitreten';

  @override
  String get roomId => 'Raum-ID';

  @override
  String get recentlyOpened => 'Zuletzt geöffnet';

  @override
  String get relativeJustNow => 'gerade eben';

  @override
  String relativeMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'vor $count Min.',
      one: 'vor 1 Min.',
    );
    return '$_temp0';
  }

  @override
  String relativeHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'vor $count Std.',
      one: 'vor 1 Std.',
    );
    return '$_temp0';
  }

  @override
  String get relativeYesterday => 'gestern';

  @override
  String relativeDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'vor $count Tagen',
    );
    return '$_temp0';
  }

  @override
  String roomTitle(String roomId) {
    return 'Raum $roomId';
  }

  @override
  String get copyRoomId => 'Raum-ID kopieren';

  @override
  String get roomIdCopied => 'Raum-ID kopiert';

  @override
  String get viewModeEdit => 'Bearbeiten';

  @override
  String get viewModeSplit => 'Geteilt';

  @override
  String get viewModeView => 'Vorschau';

  @override
  String get changelog => 'Changelog';

  @override
  String get changelogLoadError => 'Changelog konnte nicht geladen werden.';

  @override
  String get statusConnected => 'Verbunden';

  @override
  String get statusConnecting => 'Verbinde…';

  @override
  String get statusReconnecting => 'Verbinde neu…';

  @override
  String get statusDisconnected => 'Getrennt';

  @override
  String get statusError => 'Verbindungsfehler';

  @override
  String get exportDocument => 'Dokument exportieren';

  @override
  String exportAs(String format) {
    return 'Als $format exportieren';
  }

  @override
  String get exportFileName => 'Dateiname';

  @override
  String exportSaved(String fileName) {
    return '$fileName gespeichert';
  }

  @override
  String exportFailed(String error) {
    return 'Export fehlgeschlagen: $error';
  }

  @override
  String get cancel => 'Abbrechen';

  @override
  String get save => 'Speichern';

  @override
  String get shortcutUndo => 'Rückgängig';

  @override
  String get shortcutRedo => 'Wiederholen';

  @override
  String get shortcutBold => 'Fett';

  @override
  String get shortcutItalic => 'Kursiv';

  @override
  String get shortcutStrikethrough => 'Durchgestrichen';

  @override
  String get shortcutInlineCode => 'Inline-Code';

  @override
  String get shortcutHeading1 => 'Überschrift 1';

  @override
  String get shortcutHeading2 => 'Überschrift 2';

  @override
  String get shortcutHeading3 => 'Überschrift 3';

  @override
  String get shortcutQuote => 'Zitat';

  @override
  String get shortcutBulletList => 'Aufzählung';

  @override
  String get shortcutLink => 'Link';

  @override
  String get shortcutImage => 'Bild';
}
