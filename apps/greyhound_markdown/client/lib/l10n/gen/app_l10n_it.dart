// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_l10n.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppL10nIt extends AppL10n {
  AppL10nIt([String locale = 'it']) : super(locale);

  @override
  String get settings => 'Impostazioni';

  @override
  String get appearance => 'Aspetto';

  @override
  String get language => 'Lingua';

  @override
  String get editorSection => 'Editor';

  @override
  String get links => 'Collegamenti';

  @override
  String get themeLight => 'Chiaro';

  @override
  String get themeDark => 'Scuro';

  @override
  String get themeSystem => 'Sistema';

  @override
  String get languageSystem => 'Sistema';

  @override
  String get lineNumbers => 'Numeri di riga';

  @override
  String get lineNumbersSubtitle =>
      'Mostra i numeri di riga accanto al sorgente';

  @override
  String get wordWrap => 'A capo automatico';

  @override
  String get wordWrapSubtitle =>
      'Manda a capo le righe lunghe invece di scorrere di lato';

  @override
  String get viewChangelog => 'Vedi il changelog';

  @override
  String get viewLicenses => 'Vedi le licenze';

  @override
  String get versionUnknown => '—';

  @override
  String get appTagline =>
      'Un editor markdown collaborativo in tempo reale, costruito su crdt_lf.';

  @override
  String get creditPrefix => 'Powered by crdt_lf · creato da ';

  @override
  String get linkRepo => 'GitHub';

  @override
  String get linkAppSource => 'Sorgente dell\'app';

  @override
  String get linkDocs => 'Documentazione crdt_lf';

  @override
  String get yourName => 'Il tuo nome';

  @override
  String get createRoom => 'Crea una nuova stanza';

  @override
  String get join => 'Entra';

  @override
  String get roomId => 'ID della stanza';

  @override
  String get recentlyOpened => 'Aperte di recente';

  @override
  String get relativeJustNow => 'poco fa';

  @override
  String relativeMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count min fa',
      one: '1 min fa',
    );
    return '$_temp0';
  }

  @override
  String relativeHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count h fa',
      one: '1 h fa',
    );
    return '$_temp0';
  }

  @override
  String get relativeYesterday => 'ieri';

  @override
  String relativeDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count giorni fa',
    );
    return '$_temp0';
  }

  @override
  String roomTitle(String roomId) {
    return 'Stanza $roomId';
  }

  @override
  String get copyRoomId => 'Copia l\'ID della stanza';

  @override
  String get roomIdCopied => 'ID della stanza copiato';

  @override
  String get viewModeEdit => 'Modifica';

  @override
  String get viewModeSplit => 'Affiancato';

  @override
  String get viewModeView => 'Anteprima';

  @override
  String get changelog => 'Changelog';

  @override
  String get changelogLoadError => 'Impossibile caricare il changelog.';

  @override
  String get statusConnected => 'Connesso';

  @override
  String get statusConnecting => 'Connessione…';

  @override
  String get statusReconnecting => 'Riconnessione…';

  @override
  String get statusDisconnected => 'Disconnesso';

  @override
  String get statusError => 'Errore di connessione';

  @override
  String get exportDocument => 'Esporta il documento';

  @override
  String exportAs(String format) {
    return 'Esporta come $format';
  }

  @override
  String get exportFileName => 'Nome del file';

  @override
  String exportSaved(String fileName) {
    return 'Salvato $fileName';
  }

  @override
  String exportFailed(String error) {
    return 'Esportazione fallita: $error';
  }

  @override
  String get cancel => 'Annulla';

  @override
  String get save => 'Salva';

  @override
  String get shortcutUndo => 'Annulla';

  @override
  String get shortcutRedo => 'Ripristina';

  @override
  String get shortcutBold => 'Grassetto';

  @override
  String get shortcutItalic => 'Corsivo';

  @override
  String get shortcutStrikethrough => 'Barrato';

  @override
  String get shortcutInlineCode => 'Codice inline';

  @override
  String get shortcutHeading1 => 'Titolo 1';

  @override
  String get shortcutHeading2 => 'Titolo 2';

  @override
  String get shortcutHeading3 => 'Titolo 3';

  @override
  String get shortcutQuote => 'Citazione';

  @override
  String get shortcutBulletList => 'Elenco puntato';

  @override
  String get shortcutLink => 'Collegamento';

  @override
  String get shortcutImage => 'Immagine';
}
