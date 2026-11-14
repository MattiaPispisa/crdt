// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:io';

import 'open_outline.dart';
import 'outline.dart';

/// Run it twice, with two files, next to a relay such as the one of the
/// relay recipe: `dart run main.dart alice.db Intro`.
Future<void> main(List<String> args) async {
  final path = args.isEmpty ? 'outline.db' : args.first;
  final replica = await openOutline('ws://localhost:8080', path: path);

  final chapters = chaptersOf(replica.document);
  // The whole tree, every reference resolved, after each change.
  replica.document.updates.listen((_) => stdout.writeln(chapters.resolved));

  if (args.length > 1) {
    addChapter(chapters, args[1]);
  }

  await ProcessSignal.sigint.watch().first;
  await replica.close();
}
