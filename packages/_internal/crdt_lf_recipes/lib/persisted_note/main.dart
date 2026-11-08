// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

// #docregion imports
import 'dart:io';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_sqlite/crdt_lf_sqlite.dart';

// #enddocregion imports

/// Adds a line to the note stored in `note.db`, and returns the whole note.
Future<String> addLine() async {
  // #docregion open
  final backend = CRDTSqlite.open('note.db');

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
  backend.close();
  // #enddocregion close

  return value;
}

Future<void> main() async {
  // One more line on every run.
  stdout.writeln(await addLine());
}
