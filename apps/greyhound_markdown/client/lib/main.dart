import 'package:flutter/material.dart';
import 'package:highlight/highlight.dart' show highlight;
import 'package:highlight/languages/all.dart' show allLanguages;

import 'package:greyhound_markdown_client/src/config.dart';
import 'package:greyhound_markdown_client/src/screens/editor_screen.dart';
import 'package:greyhound_markdown_client/src/screens/home_screen.dart';
import 'package:greyhound_markdown_client/src/screens/settings_screen.dart';

void main() {
  // Register every grammar so fenced code blocks (```lang) highlight in the
  // preview regardless of the language the author uses.
  allLanguages.forEach(highlight.registerLanguage);
  runApp(const GreyhoundApp());
}

class GreyhoundApp extends StatelessWidget {
  const GreyhoundApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kAppName,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      onGenerateRoute: (settings) {
        final uri = Uri.parse(settings.name ?? '/');
        if (uri.pathSegments.length == 2 && uri.pathSegments.first == 'room') {
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => EditorScreen(roomId: uri.pathSegments[1]),
          );
        }
        if (uri.path == kSettingsRoute) {
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => const SettingsScreen(),
          );
        }
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const HomeScreen(),
        );
      },
    );
  }
}
