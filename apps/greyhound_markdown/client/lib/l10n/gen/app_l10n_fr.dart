// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_l10n.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppL10nFr extends AppL10n {
  AppL10nFr([String locale = 'fr']) : super(locale);

  @override
  String get settings => 'Paramètres';

  @override
  String get appearance => 'Apparence';

  @override
  String get language => 'Langue';

  @override
  String get editorSection => 'Éditeur';

  @override
  String get links => 'Liens';

  @override
  String get themeLight => 'Clair';

  @override
  String get themeDark => 'Sombre';

  @override
  String get themeSystem => 'Système';

  @override
  String get languageSystem => 'Système';

  @override
  String get lineNumbers => 'Numéros de ligne';

  @override
  String get lineNumbersSubtitle =>
      'Affiche les numéros de ligne à côté du code source';

  @override
  String get wordWrap => 'Retour à la ligne';

  @override
  String get wordWrapSubtitle =>
      'Coupe les longues lignes au lieu de défiler horizontalement';

  @override
  String get viewChangelog => 'Voir le changelog';

  @override
  String get viewLicenses => 'Voir les licences';

  @override
  String get versionUnknown => '—';

  @override
  String get appTagline =>
      'Un éditeur markdown collaboratif en temps réel, basé sur crdt_lf.';

  @override
  String get creditPrefix => 'Powered by crdt_lf · créé par ';

  @override
  String get linkRepo => 'GitHub';

  @override
  String get linkAppSource => 'Code source de l\'app';

  @override
  String get linkDocs => 'Documentation crdt_lf';

  @override
  String get yourName => 'Votre nom';

  @override
  String get createRoom => 'Créer un nouveau salon';

  @override
  String get join => 'Rejoindre';

  @override
  String get roomId => 'ID du salon';

  @override
  String get recentlyOpened => 'Ouverts récemment';

  @override
  String get relativeJustNow => 'à l\'instant';

  @override
  String relativeMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'il y a $count min',
      one: 'il y a 1 min',
    );
    return '$_temp0';
  }

  @override
  String relativeHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'il y a $count h',
      one: 'il y a 1 h',
    );
    return '$_temp0';
  }

  @override
  String get relativeYesterday => 'hier';

  @override
  String relativeDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'il y a $count jours',
    );
    return '$_temp0';
  }

  @override
  String roomTitle(String roomId) {
    return 'Salon $roomId';
  }

  @override
  String get copyRoomId => 'Copier l\'ID du salon';

  @override
  String get roomIdCopied => 'ID du salon copié';

  @override
  String get viewModeEdit => 'Modifier';

  @override
  String get viewModeSplit => 'Partagé';

  @override
  String get viewModeView => 'Aperçu';

  @override
  String get changelog => 'Changelog';

  @override
  String get changelogLoadError => 'Impossible de charger le changelog.';

  @override
  String get statusConnected => 'Connecté';

  @override
  String get statusConnecting => 'Connexion…';

  @override
  String get statusReconnecting => 'Reconnexion…';

  @override
  String get statusDisconnected => 'Déconnecté';

  @override
  String get statusError => 'Erreur de connexion';

  @override
  String get statusUnsupported => 'Mise à jour requise';

  @override
  String get exportDocument => 'Exporter le document';

  @override
  String exportAs(String format) {
    return 'Exporter en $format';
  }

  @override
  String get exportFileName => 'Nom du fichier';

  @override
  String exportSaved(String fileName) {
    return '$fileName enregistré';
  }

  @override
  String exportFailed(String error) {
    return 'Échec de l\'export : $error';
  }

  @override
  String get cancel => 'Annuler';

  @override
  String get save => 'Enregistrer';

  @override
  String get shortcutUndo => 'Annuler';

  @override
  String get shortcutRedo => 'Rétablir';

  @override
  String get shortcutBold => 'Gras';

  @override
  String get shortcutItalic => 'Italique';

  @override
  String get shortcutStrikethrough => 'Barré';

  @override
  String get shortcutInlineCode => 'Code inline';

  @override
  String get shortcutHeading1 => 'Titre 1';

  @override
  String get shortcutHeading2 => 'Titre 2';

  @override
  String get shortcutHeading3 => 'Titre 3';

  @override
  String get shortcutQuote => 'Citation';

  @override
  String get shortcutBulletList => 'Liste à puces';

  @override
  String get shortcutLink => 'Lien';

  @override
  String get shortcutImage => 'Image';
}
