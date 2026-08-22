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

/// Handler type token for the todo `done` flag.
///
/// Must equal the `handlerType` the Flutter clients register (see
/// `shared_examples_infrastructure/.../document/_state.dart`) so encoded
/// changes decode to the same handler even under dart2js minification.
const String kDoneHandlerType = 'CRDTRegisterHandler<bool>';
