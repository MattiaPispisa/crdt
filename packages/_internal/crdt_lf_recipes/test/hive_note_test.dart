// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:io';

import 'package:crdt_lf_hive/crdt_lf_hive.dart';
import 'package:crdt_lf_recipes/hive_note/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory directory;
  late Directory previous;

  setUpAll(CRDTHive.initialize);

  // `main` stores the note in the `note_db` folder of the working directory.
  setUp(() {
    previous = Directory.current;
    directory = Directory.systemTemp.createTempSync('hive_note');
    Directory.current = directory;
    Hive.init('note_db');
  });

  tearDown(() async {
    await CRDTHive.closeAllBoxes();
    Directory.current = previous;
    directory.deleteSync(recursive: true);
  });

  test('the note survives a restart', () async {
    expect(await addLine(), 'Hello 🌍\n');
    // Every box of the note is closed: the next run reads from the disk.
    expect(Hive.isBoxOpen('documents'), isFalse);
    expect(await addLine(), 'Hello 🌍\nHello 🌍\n');
  });
}
