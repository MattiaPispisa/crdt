// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:flutter/material.dart';

import 'note_page.dart';

void main() {
  runApp(
    MaterialApp(
      title: 'Note',
      home: CrdtProvider(
        // In memory: the provider creates the document and disposes it.
        create: (_) {
          final document = CRDTDocument();
          CRDTFugueTextHandler(document, 'note');
          return document;
        },
        child: const NotePage(),
      ),
    ),
  );
}
