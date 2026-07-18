import 'package:flutter/material.dart';

import 'package:greyhound_markdown_client/src/screens/editor_screen.dart';
import 'package:greyhound_markdown_client/src/screens/home_screen.dart';

void main() {
  runApp(const GreyhoundApp());
}

class GreyhoundApp extends StatelessWidget {
  const GreyhoundApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Greyhound Markdown',
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
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const HomeScreen(),
        );
      },
    );
  }
}
