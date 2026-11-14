// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

// A copy of a recipe, written by `melos run recipes_sync`.
// Edit the recipe, then run it again:
// packages/_internal/crdt_lf_recipes/lib/hive_note/main.dart

import 'dart:io';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_hive/crdt_lf_hive.dart';
import 'package:hive/hive.dart';

/// Adds a line to the stored note, and returns the whole note.
Future<String> addLine() async {
  final backend = await CRDTHive.open();

  // Reads the stored note (or starts an empty one), then writes every edit.
  final note = await backend.openDocument('note');
  final text = CRDTFugueTextHandler(note.document, 'body');

  text.insert(text.value.runes.length, 'Hello 🌍\n');
  final value = text.value;

  await note.persistence.dispose(); // writes what is still waiting
  note.document.dispose();
  await note.persistence.storage.close();
  await backend.close();

  return value;
}

Future<void> main() async {
  // Once per process, before the first open.
  Hive.init('note_db');
  CRDTHive.initialize();

  // One more line on every run.
  stdout.writeln(await addLine());
}
