/// Example document/handler ids the demo server shares with the Flutter
/// example clients.
///
/// This is a Dart-only mirror of
/// `shared_examples_infrastructure/lib/examples/ids.dart`. The demo server is a
/// pure-Dart package and cannot depend on that (Flutter) package, so the two
/// declare matching constants — keep them in sync.
library;

/// CRDT handler ids used by the example states.
abstract final class ExampleHandlerIds {
  /// Todo list handler id.
  static const String todoList = 'todo-list';

  /// Sortable todo list handler id.
  static const String sortableTodoList = 'sortable-todo-list';

  /// Document (nested refs) root handler id.
  static const String document = 'document';
}

/// Document ids used by the socket client + server to address each example.
abstract final class ExampleDocumentIds {
  /// Todo list document id.
  static const String todoList = 'a1b2c3d4-0001-4000-8000-000000000001';

  /// Sortable todo list document id.
  static const String sortableTodoList = 'a1b2c3d4-0001-4000-8000-000000000002';

  /// Document (nested refs) document id.
  static const String document = 'a1b2c3d4-0001-4000-8000-000000000003';
}

/// CRDT handler **kinds** used by the example states.
///
/// A kind travels in every operation envelope, so these must equal
/// `ExampleHandlerTypes` in the mirrored file. A handler whose kind differs
/// ignores every change addressed to it, in silence.
abstract final class ExampleHandlerTypes {
  /// Kind of the plain todo list.
  static const String todoList = 'todo.list';

  /// Kind of the sortable todo list.
  static const String sortableTodoList = 'todo.sortable-list';

  /// Kind of the `done` flag nested under a todo.
  static const String done = 'todo.done';
}
