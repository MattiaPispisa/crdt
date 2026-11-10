// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf_hive/crdt_lf_hive.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import 'editor_page.dart';

// #docregion app
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // On the web Hive uses IndexedDB and needs no path.
  if (!kIsWeb) {
    Hive.init((await getApplicationDocumentsDirectory()).path);
  }
  CRDTHive.initialize();
  final backend = await CRDTHive.open();

  runApp(EditorApp(backend: backend));
}

/// The app: one rich text page stored in [backend].
class EditorApp extends StatelessWidget {
  /// Creates the app of the page stored in [backend].
  const EditorApp({required this.backend, super.key});

  /// Where the page is stored.
  final CRDTStorageBackend backend;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Editor',
      // flutter_quill reads its texts from here, and throws without them.
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      home: EditorPage(backend: backend),
    );
  }
}
// #enddocregion app
