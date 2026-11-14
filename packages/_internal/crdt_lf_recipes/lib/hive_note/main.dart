// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:io';

// #docregion imports
import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_hive/crdt_lf_hive.dart';
import 'package:hive/hive.dart';

// #enddocregion imports

/// Adds a line to the stored note, and returns the whole note.
Future<String> addLine() async {
  // #docregion open
  final backend = await CRDTHive.open();

  // Reads the stored note (or starts an empty one), then writes every edit.
  final note = await backend.openDocument('note');
  final text = CRDTFugueTextHandler(note.document, 'body');
  // #enddocregion open

  // #docregion edit
  text.insert(text.value.runes.length, 'Hello 🌍\n');
  // #enddocregion edit
  final value = text.value;

  // #docregion close
  await note.persistence.dispose(); // writes what is still waiting
  note.document.dispose();
  await note.persistence.storage.close();
  await backend.close();
  // #enddocregion close

  return value;
}

Future<void> main() async {
  // #docregion init
  // Once per process, before the first open.
  Hive.init('note_db');
  CRDTHive.initialize();
  // #enddocregion init

  // One more line on every run.
  stdout.writeln(await addLine());
}
