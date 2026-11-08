// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';

import 'note_page.dart';
import 'presence.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The relay of server.dart. Run the app twice to see the other caret.
  final note = await joinNote(
    'ws://localhost:8080',
    name: 'Guest ${DateTime.now().second}',
    color: Colors.primaries[DateTime.now().second % Colors.primaries.length],
  );

  // MaterialApp gives the Overlay the cursors are painted into.
  runApp(MaterialApp(title: 'Note', home: NotePage(note: note)));
}
