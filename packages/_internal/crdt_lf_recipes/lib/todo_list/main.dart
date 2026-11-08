// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:flutter/material.dart';

import 'todo_page.dart';
import 'todos.dart';

void main() {
  runApp(
    MaterialApp(
      title: 'Todos',
      // #docregion provide
      home: CrdtProvider(
        // In memory: the provider creates the document and disposes it.
        create: (_) {
          final document = CRDTDocument();
          todosOf(document); // the widgets read the list under 'todos'
          return document;
        },
        child: const TodoPage(),
      ),
      // #enddocregion provide
    ),
  );
}
