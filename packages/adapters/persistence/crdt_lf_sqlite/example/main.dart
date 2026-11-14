// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

// A copy of a recipe, written by `melos run recipes_sync`.
// Edit the recipe, then run it again:
// packages/_internal/crdt_lf_recipes/lib/persisted_note/main.dart

import 'dart:io';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_sqlite/crdt_lf_sqlite.dart';

/// Adds a line to the note stored in `note.db`, and returns the whole note.
Future<String> addLine() async {
  final backend = CRDTSqlite.open('note.db');

  // Reads the stored note (or starts an empty one), then writes every edit.
  final note = await backend.openDocument('note');
  final text = CRDTFugueTextHandler(note.document, 'body');

  text.insert(text.value.runes.length, 'Hello 🌍\n');
  final value = text.value;

  await note.persistence.dispose(); // writes what is still waiting
  note.document.dispose();
  await note.persistence.storage.close();
  backend.close();

  return value;
}

Future<void> main() async {
  // One more line on every run.
  stdout.writeln(await addLine());
}
