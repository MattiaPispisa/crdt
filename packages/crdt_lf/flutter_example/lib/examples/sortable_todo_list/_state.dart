import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter_example/shared/example_document.dart';

/// JSON shape stored in the CRDT list for each todo.
typedef EncodedTodoListType = Map<String, dynamic>;

const _kSortableTodoListDocumentId = 'sortable-todo-list';

/// Document controller for the sortable todo list example.
///
/// Backed by a [CRDTFugueMovableListHandler], which adds an explicit [reorder]
/// (move) operation that preserves element identity: two peers moving the same
/// item concurrently converge to a single position instead of duplicating it
/// (which a delete + re-insert on a plain list would do).
class SortableDocumentState
    extends ExampleDocument<CRDTFugueMovableListHandler<EncodedTodoListType>> {
  /// Creates a sortable todo document for [author] wired to [network].
  SortableDocumentState({required super.author, required super.network});

  @override
  CRDTFugueMovableListHandler<EncodedTodoListType> createHandler(
    BaseCRDTDocument doc,
  ) {
    return CRDTFugueMovableListHandler<EncodedTodoListType>(
      doc,
      _kSortableTodoListDocumentId,
    );
  }

  /// The current todos (live or time-travel view).
  List<Todo> get todos => handler.value.map(Todo.fromJson).toList();

  /// Adds a new todo item at the top.
  void addTodo(String todo) {
    liveHandler.insert(0, Todo(text: todo).toJson());
  }

  /// Removes the todo at [index].
  void removeTodo(int index) {
    liveHandler.delete(index);
  }

  /// Toggles the done status of the todo at [index].
  void toggleTodo(int index) {
    final todo = Todo.fromJson(liveHandler.value[index]);
    liveHandler.update(index, todo.copyWith(isDone: !todo.isDone).toJson());
  }

  /// Moves the todo from visible index [from] to visible index [to].
  ///
  /// [to] is the destination index in the list **after** the moved item is
  /// removed (the same convention as `ReorderableListView` once its index is
  /// adjusted), and matches [CRDTFugueMovableListHandler.move].
  void reorder(int from, int to) {
    liveHandler.move(from, to);
  }
}

/// A todo item.
class Todo {
  /// Creates a todo.
  const Todo({required this.text, this.isDone = false});

  /// Decodes a todo from its JSON shape.
  factory Todo.fromJson(EncodedTodoListType json) {
    return Todo(text: json['text'] as String, isDone: json['isDone'] as bool);
  }

  /// The todo text.
  final String text;

  /// Whether the todo is done.
  final bool isDone;

  /// Encodes this todo to its JSON shape.
  EncodedTodoListType toJson() => {'text': text, 'isDone': isDone};

  /// Returns a copy with the given fields replaced.
  Todo copyWith({String? text, bool? isDone}) {
    return Todo(text: text ?? this.text, isDone: isDone ?? this.isDone);
  }

  @override
  String toString() => 'Todo(text: $text, isDone: $isDone)';
}
