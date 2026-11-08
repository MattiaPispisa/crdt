// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:io';

import 'package:crdt_lf_recipes/persisted_note/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late Directory previous;

  // The recipe writes `note.db` in the working directory.
  setUp(() {
    previous = Directory.current;
    directory = Directory.systemTemp.createTempSync('persisted_note');
    Directory.current = directory;
  });

  tearDown(() {
    Directory.current = previous;
    directory.deleteSync(recursive: true);
  });

  test('the note survives a restart', () async {
    expect(await addLine(), 'Hello 🌍\n');
    expect(await addLine(), 'Hello 🌍\nHello 🌍\n');
  });
}
