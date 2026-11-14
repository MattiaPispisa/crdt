// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf_hive/crdt_lf_hive.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';

import 'note_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // On the web Hive uses IndexedDB and needs no path.
  if (!kIsWeb) {
    Hive.init((await getApplicationDocumentsDirectory()).path);
  }
  CRDTHive.initialize();

  runApp(
    MaterialApp(
      title: 'Note',
      // MaterialApp gives the Overlay the cursors are painted into.
      home: NotePage(
        // The relay of server.dart. Each peer needs its own storage: run the
        // app on two devices, or in two browsers.
        url: 'ws://localhost:8080',
        name: 'Guest ${DateTime.now().second}',
        color:
            Colors.primaries[DateTime.now().second % Colors.primaries.length],
      ),
    ),
  );
}
