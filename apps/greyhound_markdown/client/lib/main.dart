import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:highlight/highlight.dart' show highlight;
import 'package:highlight/languages/all.dart' show allLanguages;
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:path_provider/path_provider.dart';

import 'package:greyhound_markdown_client/src/application/application.dart';
import 'package:greyhound_markdown_client/src/config.dart';
import 'package:greyhound_markdown_client/src/screens/changelog_screen.dart';
import 'package:greyhound_markdown_client/src/screens/editor_screen.dart';
import 'package:greyhound_markdown_client/src/screens/home_screen.dart';
import 'package:greyhound_markdown_client/src/screens/settings_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Register every grammar so fenced code blocks (```lang) highlight in the
  // preview regardless of the language the author uses.
  allLanguages.forEach(highlight.registerLanguage);

  // Backs [UserSettingsCubit]. The documents directory rather than the
  // temporary one: preferences have to survive an OS cleanup.
  HydratedBloc.storage = await HydratedStorage.build(
    storageDirectory: kIsWeb
        ? HydratedStorageDirectory.web
        : HydratedStorageDirectory(
            (await getApplicationDocumentsDirectory()).path,
          ),
  );

  runApp(const GreyhoundApp());
}

/// The app theme for [brightness], seeded from a single color so light and
/// dark stay two views of the same palette.
ThemeData greyhoundTheme(Brightness brightness) {
  return ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: Colors.teal,
      brightness: brightness,
    ),
  );
}

class GreyhoundApp extends StatelessWidget {
  const GreyhoundApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Above the MaterialApp so every route — including the ones pushed by
    // onGenerateRoute — reads the same settings.
    return BlocProvider(
      create: (_) => UserSettingsCubit(),
      // Only the theme mode is read here, so typing a name does not rebuild
      // the whole app.
      child: BlocSelector<UserSettingsCubit, UserSettingsState, ThemeMode>(
        selector: (userSettings) => userSettings.themeMode,
        builder: (context, themeMode) => MaterialApp(
          title: kAppName,
          theme: greyhoundTheme(Brightness.light),
          darkTheme: greyhoundTheme(Brightness.dark),
          themeMode: themeMode,
          onGenerateRoute: (settings) {
            final uri = Uri.parse(settings.name ?? '/');
            final roomId = parseRoomRoute(uri);
            if (roomId != null) {
              return MaterialPageRoute(
                settings: settings,
                builder: (_) => EditorScreen(roomId: roomId),
              );
            }
            if (uri.path == kSettingsRoute) {
              return MaterialPageRoute(
                settings: settings,
                builder: (_) => const SettingsScreen(),
              );
            }
            if (uri.path == kChangelogRoute) {
              return MaterialPageRoute(
                settings: settings,
                builder: (_) => const ChangelogScreen(),
              );
            }
            // Anything else — including a `/room/…` link whose id is not one
            // — lands on the home page rather than on a broken room.
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => const HomeScreen(),
            );
          },
        ),
      ),
    );
  }
}
