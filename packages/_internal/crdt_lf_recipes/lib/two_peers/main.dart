// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

// #docregion imports
import 'dart:io';

import 'package:crdt_lf/crdt_lf.dart';

// #enddocregion imports

/// Lets two peers write at the same spot of one text, with no connection, and
/// returns what each reads after they merge.
(String, String) mergeTwoPeers() {
  // #docregion merge
  final alice = CRDTDocument();
  final bob = CRDTDocument();

  // The same handler id: the same text.
  final aliceText = CRDTFugueTextHandler(alice, 'note');
  final bobText = CRDTFugueTextHandler(bob, 'note');

  aliceText.insert(0, 'Hello');
  bob.importChanges(alice.exportChanges());

  // A conflict: both write after "Hello", offline.
  aliceText.insert(5, ' World');
  bobText.insert(5, ' Dart');

  // They meet again and exchange their changes.
  bob.importChanges(alice.exportChanges());
  alice.importChanges(bob.exportChanges());

  // Each insert stays whole: never "Hello W Doarrltd".
  // The peer ids pick which one comes first, so both
  // print Hello World Dart, or both Hello Dart World.
  stdout
    ..writeln(aliceText.value)
    ..writeln(bobText.value);
  // #enddocregion merge

  final result = (aliceText.value, bobText.value);
  alice.dispose();
  bob.dispose();
  return result;
}

void main() {
  mergeTwoPeers();
}
