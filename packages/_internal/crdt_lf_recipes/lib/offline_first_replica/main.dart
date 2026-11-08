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

  // #docregion init
  // On the web Hive uses IndexedDB and needs no path.
  if (!kIsWeb) {
    Hive.init((await getApplicationDocumentsDirectory()).path);
  }
  CRDTHive.initialize();
  // #enddocregion init

  runApp(
    const MaterialApp(
      title: 'Note',
      // A relay server, such as WebSocketRelayServer of crdt_socket_sync.
      home: NotePage(url: 'ws://localhost:8080'),
    ),
  );
}
