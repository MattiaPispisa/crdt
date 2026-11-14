// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

// #docregion model
import 'package:crdt_lf/crdt_lf.dart';

/// The kind of the `done` flag. A generic handler needs a tag: write it once.
final doneKind = CRDTRegisterHandler.spec<bool>('todo.done');

/// The todo list of [document]: a movable list with one map per todo.
CRDTMovableListRefHandler todosOf(CRDTDocument document) {
  // The kinds this peer must rebuild when the todos of another peer arrive.
  document
    ..register(CRDTMapRefHandler.spec)
    ..register(CRDTFugueTextHandler.spec)
    ..register(doneKind);
  return document.handler(CRDTMovableListRefHandler.spec, 'todos');
}

/// Adds a todo that reads [text] at the end of [todos].
CRDTMapRefHandler addTodo(CRDTMovableListRefHandler todos, {String text = ''}) {
  // One transaction: the other peers get the todo with both its fields.
  return todos.doc.runInTransaction(() {
    final todo = todos.insertChild(
      todos.childRefs().length,
      CRDTMapRefHandler.spec,
    );
    final title = todo.child('text', CRDTFugueTextHandler.spec);
    if (text.isNotEmpty) {
      title.insert(0, text);
    }
    todo.child('done', doneKind).set(false);
    return todo;
  });
}

/// The fields of one todo, each merged on its own.
extension TodoFields on CRDTMapRefHandler {
  /// The text of the todo: merged character by character.
  CRDTFugueTextHandler get text => child('text', CRDTFugueTextHandler.spec);

  /// Whether the todo is done: the last write wins.
  CRDTRegisterHandler<bool> get done => child('done', doneKind);
}
// #enddocregion model
