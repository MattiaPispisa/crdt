import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_l10n_en.dart';
import 'app_l10n_it.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppL10n
/// returned by `AppL10n.of(context)`.
///
/// Applications need to include `AppL10n.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_l10n.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppL10n.localizationsDelegates,
///   supportedLocales: AppL10n.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppL10n.supportedLocales
/// property.
abstract class AppL10n {
  AppL10n(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppL10n of(BuildContext context) {
    return Localizations.of<AppL10n>(context, AppL10n)!;
  }

  static const LocalizationsDelegate<AppL10n> delegate = _AppL10nDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('it'),
  ];

  /// Title of the settings page, and the footer entry to it.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// Settings section holding the theme mode.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// Settings section holding the language picker.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// Settings section holding the editor view options.
  ///
  /// In en, this message translates to:
  /// **'Editor'**
  String get editorSection;

  /// Settings section holding the project links.
  ///
  /// In en, this message translates to:
  /// **'Links'**
  String get links;

  /// Theme mode: always the light palette.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// Theme mode: always the dark palette.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// Theme mode: follow the device setting.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get themeSystem;

  /// Language choice: follow the device language.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get languageSystem;

  /// Editor option: draw a numbered gutter.
  ///
  /// In en, this message translates to:
  /// **'Line numbers'**
  String get lineNumbers;

  /// Subtitle of the line numbers option.
  ///
  /// In en, this message translates to:
  /// **'Show a numbered gutter next to the source'**
  String get lineNumbersSubtitle;

  /// Editor option: wrap long lines.
  ///
  /// In en, this message translates to:
  /// **'Word wrap'**
  String get wordWrap;

  /// Subtitle of the word wrap option.
  ///
  /// In en, this message translates to:
  /// **'Wrap long lines instead of scrolling sideways'**
  String get wordWrapSubtitle;

  /// Button opening the changelog page.
  ///
  /// In en, this message translates to:
  /// **'View changelog'**
  String get viewChangelog;

  /// Button opening the open-source licenses page.
  ///
  /// In en, this message translates to:
  /// **'View licenses'**
  String get viewLicenses;

  /// Placeholder shown while the app version is still loading.
  ///
  /// In en, this message translates to:
  /// **'—'**
  String get versionUnknown;

  /// One-line description of the app on the settings page.
  ///
  /// In en, this message translates to:
  /// **'A real-time collaborative markdown editor built on crdt_lf.'**
  String get appTagline;

  /// Credit line, up to the author's name, which follows it as a link.
  ///
  /// In en, this message translates to:
  /// **'Powered by crdt_lf · created by '**
  String get creditPrefix;

  /// Link to the monorepo on GitHub.
  ///
  /// In en, this message translates to:
  /// **'GitHub'**
  String get linkRepo;

  /// Link to this app's own source folder.
  ///
  /// In en, this message translates to:
  /// **'App source'**
  String get linkAppSource;

  /// Link to the crdt_lf documentation site.
  ///
  /// In en, this message translates to:
  /// **'crdt_lf docs'**
  String get linkDocs;

  /// Home screen field for the name shown to the other peers.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get yourName;

  /// Home screen button opening a brand new room.
  ///
  /// In en, this message translates to:
  /// **'Create a new room'**
  String get createRoom;

  /// Home screen button entering the room whose id is typed.
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get join;

  /// Home screen field for the id of the room to join.
  ///
  /// In en, this message translates to:
  /// **'Room id'**
  String get roomId;

  /// Header of the recently opened rooms list.
  ///
  /// In en, this message translates to:
  /// **'Recently opened'**
  String get recentlyOpened;

  /// A room opened less than a minute ago.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get relativeJustNow;

  /// How many minutes ago a room was opened.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 min ago} other{{count} min ago}}'**
  String relativeMinutesAgo(int count);

  /// How many hours ago a room was opened.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 h ago} other{{count} h ago}}'**
  String relativeHoursAgo(int count);

  /// A room opened one day ago.
  ///
  /// In en, this message translates to:
  /// **'yesterday'**
  String get relativeYesterday;

  /// How many days ago a room was opened. Only ever 2 to 6 days: one day reads as yesterday, and a week or more shows the date.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{{count} days ago}}'**
  String relativeDaysAgo(int count);

  /// Editor app bar title.
  ///
  /// In en, this message translates to:
  /// **'Room {roomId}'**
  String roomTitle(String roomId);

  /// Tooltip of the editor button copying the room id.
  ///
  /// In en, this message translates to:
  /// **'Copy room id'**
  String get copyRoomId;

  /// Confirmation shown after the room id was copied.
  ///
  /// In en, this message translates to:
  /// **'Room id copied'**
  String get roomIdCopied;

  /// Editor layout: the source only.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get viewModeEdit;

  /// Editor layout: source and preview side by side.
  ///
  /// In en, this message translates to:
  /// **'Split'**
  String get viewModeSplit;

  /// Editor layout: the preview only.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get viewModeView;

  /// Title of the changelog page.
  ///
  /// In en, this message translates to:
  /// **'Changelog'**
  String get changelog;

  /// Shown when the bundled changelog cannot be read.
  ///
  /// In en, this message translates to:
  /// **'Could not load the changelog.'**
  String get changelogLoadError;

  /// The room is in sync with the relay.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get statusConnected;

  /// The first connection to the relay is being opened.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get statusConnecting;

  /// The connection dropped and is being opened again.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting…'**
  String get statusReconnecting;

  /// There is no connection to the relay.
  ///
  /// In en, this message translates to:
  /// **'Disconnected'**
  String get statusDisconnected;

  /// The connection to the relay failed.
  ///
  /// In en, this message translates to:
  /// **'Connection error'**
  String get statusError;

  /// Tooltip of the export button in the editor app bar.
  ///
  /// In en, this message translates to:
  /// **'Export document'**
  String get exportDocument;

  /// Title of the export dialog.
  ///
  /// In en, this message translates to:
  /// **'Export as {format}'**
  String exportAs(String format);

  /// Export dialog field for the name to save the file under.
  ///
  /// In en, this message translates to:
  /// **'File name'**
  String get exportFileName;

  /// Confirmation shown after a file was saved.
  ///
  /// In en, this message translates to:
  /// **'Saved {fileName}'**
  String exportSaved(String fileName);

  /// Shown when rendering or saving the file threw.
  ///
  /// In en, this message translates to:
  /// **'Export failed: {error}'**
  String exportFailed(String error);

  /// Dismisses a dialog without doing anything.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Confirms the export dialog.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// Editor toolbar: take back the last edit.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get shortcutUndo;

  /// Editor toolbar: write back the edit that was taken away.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get shortcutRedo;

  /// Editor toolbar: bold the selection.
  ///
  /// In en, this message translates to:
  /// **'Bold'**
  String get shortcutBold;

  /// Editor toolbar: italicize the selection.
  ///
  /// In en, this message translates to:
  /// **'Italic'**
  String get shortcutItalic;

  /// Editor toolbar: strike the selection through.
  ///
  /// In en, this message translates to:
  /// **'Strikethrough'**
  String get shortcutStrikethrough;

  /// Editor toolbar: mark the selection as code.
  ///
  /// In en, this message translates to:
  /// **'Inline code'**
  String get shortcutInlineCode;

  /// Editor toolbar: turn the line into a top-level heading.
  ///
  /// In en, this message translates to:
  /// **'Heading 1'**
  String get shortcutHeading1;

  /// Editor toolbar: turn the line into a second-level heading.
  ///
  /// In en, this message translates to:
  /// **'Heading 2'**
  String get shortcutHeading2;

  /// Editor toolbar: turn the line into a third-level heading.
  ///
  /// In en, this message translates to:
  /// **'Heading 3'**
  String get shortcutHeading3;

  /// Editor toolbar: turn the line into a block quote.
  ///
  /// In en, this message translates to:
  /// **'Quote'**
  String get shortcutQuote;

  /// Editor toolbar: turn the line into a list item.
  ///
  /// In en, this message translates to:
  /// **'Bullet list'**
  String get shortcutBulletList;

  /// Editor toolbar: wrap the selection in a link.
  ///
  /// In en, this message translates to:
  /// **'Link'**
  String get shortcutLink;

  /// Editor toolbar: wrap the selection in an image.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get shortcutImage;
}

class _AppL10nDelegate extends LocalizationsDelegate<AppL10n> {
  const _AppL10nDelegate();

  @override
  Future<AppL10n> load(Locale locale) {
    return SynchronousFuture<AppL10n>(lookupAppL10n(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'it'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppL10nDelegate old) => false;
}

AppL10n lookupAppL10n(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppL10nEn();
    case 'it':
      return AppL10nIt();
  }

  throw FlutterError(
    'AppL10n.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
