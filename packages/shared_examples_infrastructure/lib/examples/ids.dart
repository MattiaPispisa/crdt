/// Canonical identifiers shared by the example screens.
///
/// [ExampleHandlerIds] are the CRDT handler ids used inside each example's
/// `DocumentState`. [ExampleDocumentIds] are the document ids the socket client
/// and the demo server must agree on to sync the same document.
///
/// The crdt_socket_sync demo server cannot depend on this (Flutter) package, so
/// it redeclares matching constants — keep the two in sync.
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
