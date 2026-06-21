import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter_example/shared/example_document.dart';

/// JSON shape stored in the CRDT list for each todo.
typedef EncodedTodoListType = Map<String, dynamic>;

const _kTodoListDocumentId = 'todo-list';

/// Document controller for the plain todo list example.
///
/// Backed by a [CRDTListHandler]: concurrent edits merge conflict-free, but
/// there is no move operation (use the sortable example for that).
class DocumentState extends ExampleDocument<CRDTListHandler<EncodedTodoListType>> {
  /// Creates a todo document for [author] wired to [network].
  DocumentState({required super.author, required super.network});

  @override
  CRDTListHandler<EncodedTodoListType> createHandler(BaseCRDTDocument doc) {
    return CRDTListHandler<EncodedTodoListType>(doc, _kTodoListDocumentId);
  }

  /// The current todos (live or time-travel view).
  List<Todo> get todos => handler.value.map(Todo.fromJson).toList();

  /// Adds a new todo item at the top.
  void addTodo(String todo) {
    liveHandler.insert(0, Todo(text: todo).toJson());
  }

  /// Removes the todo at [index].
  void removeTodo(int index) {
    liveHandler.delete(index, 1);
  }

  /// Toggles the done status of the todo at [index].
  void toggleTodo(int index) {
    final todo = Todo.fromJson(liveHandler.value[index]);
    liveHandler.update(index, todo.copyWith(isDone: !todo.isDone).toJson());
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
