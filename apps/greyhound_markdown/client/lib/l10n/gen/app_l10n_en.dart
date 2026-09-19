// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_l10n.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppL10nEn extends AppL10n {
  AppL10nEn([String locale = 'en']) : super(locale);

  @override
  String get settings => 'Settings';

  @override
  String get appearance => 'Appearance';

  @override
  String get language => 'Language';

  @override
  String get editorSection => 'Editor';

  @override
  String get links => 'Links';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeSystem => 'System';

  @override
  String get languageSystem => 'System';

  @override
  String get lineNumbers => 'Line numbers';

  @override
  String get lineNumbersSubtitle => 'Show a numbered gutter next to the source';

  @override
  String get wordWrap => 'Word wrap';

  @override
  String get wordWrapSubtitle =>
      'Wrap long lines instead of scrolling sideways';

  @override
  String get viewChangelog => 'View changelog';

  @override
  String get viewLicenses => 'View licenses';

  @override
  String get versionUnknown => '—';

  @override
  String get appTagline =>
      'A real-time collaborative markdown editor built on crdt_lf.';

  @override
  String get creditPrefix => 'Powered by crdt_lf · created by ';

  @override
  String get linkRepo => 'GitHub';

  @override
  String get linkAppSource => 'App source';

  @override
  String get linkDocs => 'crdt_lf docs';

  @override
  String get yourName => 'Your name';

  @override
  String get createRoom => 'Create a new room';

  @override
  String get join => 'Join';

  @override
  String get roomId => 'Room id';

  @override
  String get recentlyOpened => 'Recently opened';

  @override
  String get relativeJustNow => 'just now';

  @override
  String relativeMinutesAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count min ago',
      one: '1 min ago',
    );
    return '$_temp0';
  }

  @override
  String relativeHoursAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count h ago',
      one: '1 h ago',
    );
    return '$_temp0';
  }

  @override
  String get relativeYesterday => 'yesterday';

  @override
  String relativeDaysAgo(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days ago',
    );
    return '$_temp0';
  }

  @override
  String roomTitle(String roomId) {
    return 'Room $roomId';
  }

  @override
  String get copyRoomId => 'Copy room id';

  @override
  String get roomIdCopied => 'Room id copied';

  @override
  String get viewModeEdit => 'Edit';

  @override
  String get viewModeSplit => 'Split';

  @override
  String get viewModeView => 'View';

  @override
  String get changelog => 'Changelog';

  @override
  String get changelogLoadError => 'Could not load the changelog.';

  @override
  String get statusConnected => 'Connected';

  @override
  String get statusConnecting => 'Connecting…';

  @override
  String get statusReconnecting => 'Reconnecting…';

  @override
  String get statusDisconnected => 'Disconnected';

  @override
  String get statusError => 'Connection error';

  @override
  String get statusUnsupported => 'Update required';

  @override
  String get exportDocument => 'Export document';

  @override
  String exportAs(String format) {
    return 'Export as $format';
  }

  @override
  String get exportFileName => 'File name';

  @override
  String exportSaved(String fileName) {
    return 'Saved $fileName';
  }

  @override
  String exportFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get shortcutUndo => 'Undo';

  @override
  String get shortcutRedo => 'Redo';

  @override
  String get shortcutBold => 'Bold';

  @override
  String get shortcutItalic => 'Italic';

  @override
  String get shortcutStrikethrough => 'Strikethrough';

  @override
  String get shortcutInlineCode => 'Inline code';

  @override
  String get shortcutHeading1 => 'Heading 1';

  @override
  String get shortcutHeading2 => 'Heading 2';

  @override
  String get shortcutHeading3 => 'Heading 3';

  @override
  String get shortcutQuote => 'Quote';

  @override
  String get shortcutBulletList => 'Bullet list';

  @override
  String get shortcutLink => 'Link';

  @override
  String get shortcutImage => 'Image';
}
