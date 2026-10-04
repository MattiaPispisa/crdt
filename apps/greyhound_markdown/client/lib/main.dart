import 'package:crdt_lf_hive/crdt_lf_hive.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:hydrated_bloc/hydrated_bloc.dart';
import 'package:path_provider/path_provider.dart';

import 'package:greyhound_markdown_client/l10n/gen/app_l10n.dart';
import 'package:greyhound_markdown_client/src/application/application.dart';
import 'package:greyhound_markdown_client/src/config.dart';
import 'package:greyhound_markdown_client/src/di/service_locator.dart';
import 'package:greyhound_markdown_client/src/logging/app_logger.dart';
import 'package:greyhound_markdown_client/src/widgets/code_element_builder.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  setupServiceLocator();
  final logger = loggerFor(LogScope.app);

  // Backs [UserSettingsCubit]. The documents directory rather than the
  // temporary one: preferences have to survive an OS cleanup.
  HydratedBloc.storage = await HydratedStorage.build(
    storageDirectory: kIsWeb
        ? HydratedStorageDirectory.web
        : HydratedStorageDirectory(
            (await getApplicationDocumentsDirectory()).path,
          ),
  );
  logger.info('Settings storage ready');

  // Backs the per-room document cache, so a reload without a connection
  // reopens the room instead of an empty page.
  CRDTHive.initialize();
  logger.info('Room storage ready');

  runApp(const GreyhoundApp());
  logger.info('App started, relay server at $kServerUrl');

  // Not before runApp: this is tens of milliseconds of work, and nothing on
  // screen needs it until the first code block. See `warmUpHighlight`.
  WidgetsBinding.instance.addPostFrameCallback((_) => warmUpHighlight());
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
    // Above the MaterialApp so every route reads the same settings.
    return BlocProvider(
      create: (_) => UserSettingsCubit(),
      // Only what the MaterialApp itself needs is read here, so typing a name
      // does not rebuild the whole app. A record compares by value, so the
      // selector still filters out every other change.
      child: BlocSelector<UserSettingsCubit, UserSettingsState, _Appearance>(
        selector: (userSettings) => (
          themeMode: userSettings.themeMode,
          language: userSettings.language,
        ),
        builder: (context, appearance) => MaterialApp.router(
          title: kAppName,
          theme: greyhoundTheme(Brightness.light),
          darkTheme: greyhoundTheme(Brightness.dark),
          debugShowCheckedModeBanner: false,
          themeMode: appearance.themeMode,
          // `null` on AppLanguage.system: the framework then resolves the
          // device language against supportedLocales.
          locale: appearance.language.locale,
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          routerConfig: getIt<GoRouter>(),
        ),
      ),
    );
  }
}

/// What the [MaterialApp] itself reads from the user's settings.
typedef _Appearance = ({ThemeMode themeMode, AppLanguage language});
