// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

// #docregion imports
import 'dart:io';

import 'package:crdt_lf/crdt_lf.dart';

// #enddocregion imports

/// Lets two peers edit one text at the same time, and returns what each reads.
(String, String) mergeTwoPeers() {
  // #docregion merge
  final alice = CRDTDocument();
  final bob = CRDTDocument();

  // The same handler id on both peers: it is the same text.
  final aliceText = CRDTFugueTextHandler(alice, 'note');
  final bobText = CRDTFugueTextHandler(bob, 'note');

  aliceText.insert(0, 'Hello world');
  bob.importChanges(alice.exportChanges()); // Bob now reads "Hello world"

  // Both edit at the same time, with no connection.
  aliceText.insert(0, 'Big ');
  bobText.insert(11, '!');

  // They meet again and exchange what the other is missing.
  bob.importChanges(alice.exportChanges());
  alice.importChanges(bob.exportChanges());

  stdout
    ..writeln(aliceText.value) // Big Hello world!
    ..writeln(bobText.value); // Big Hello world!
  // #enddocregion merge

  final result = (aliceText.value, bobText.value);
  alice.dispose();
  bob.dispose();
  return result;
}

void main() {
  mergeTwoPeers();
}
