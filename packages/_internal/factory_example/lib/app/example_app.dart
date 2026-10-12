import 'dart:async';

import 'package:factory_example/app/example_environment.dart';
import 'package:factory_example/app/example_sync.dart';
import 'package:factory_example/examples/examples.dart';
import 'package:factory_example/examples/examples_home.dart';
import 'package:factory_example/shared/app_bar_links.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The whole example app: a home page listing the examples, and one screen
/// per example.
///
/// Each screen shows one pane per peer of [sync]. A pane opens its document
/// with `CRDTReplica`, from [storage], and syncs it with [sync].
class ExampleApp extends StatefulWidget {
  /// Creates the example app.
  const ExampleApp({
    required this.title,
    required this.logo,
    required this.links,
    required this.primaryColor,
    required this.sync,
    super.key,
    this.versions = const [],
    this.storage,
  });

  /// The app and home page title.
  final String title;

  /// The brand logo at the top of the home page.
  final Widget logo;

  /// The package versions shown under the logo.
  final List<PackageVersion> versions;

  /// The external links shown in every app bar.
  final AppBarLinks links;

  /// The seed of the theme, also used as the app-bar color.
  final Color primaryColor;

  /// How the documents reach the other peers.
  final ExampleSync sync;

  /// Where each peer keeps its documents; `null` keeps them in memory.
  final ExampleStorage? storage;

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  late final ExampleEnvironment _environment;

  @override
  void initState() {
    super.initState();
    _environment = ExampleEnvironment(
      sync: widget.sync,
      links: widget.links,
      storage: widget.storage,
    );
  }

  @override
  void dispose() {
    unawaited(_environment.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = widget.primaryColor;
    return Provider<ExampleEnvironment>.value(
      value: _environment,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: widget.title,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: primary,
            primary: primary,
          ),
          listTileTheme: const ListTileThemeData(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
          ),
          scaffoldBackgroundColor: Colors.white,
          appBarTheme: AppBarTheme(
            backgroundColor: primary,
            foregroundColor: Colors.white,
          ),
          tabBarTheme: const TabBarThemeData(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
          ),
        ),
        initialRoute: '/',
        routes: {
          '/':
              (context) => ExamplesHome(
                title: widget.title,
                logo: widget.logo,
                versions: widget.versions,
                examples: kExampleScreens,
                actions: [widget.sync.buildSettings(context), widget.links],
              ),
          for (final screen in kExampleScreens) screen.path: screen.build,
        },
      ),
    );
  }
}
