// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:convert';
import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';

// #docregion state
/// One todo, addressed by the id of the event that added it.
final class Todo {
  /// Creates the todo [id].
  const Todo(this.id, this.text, {this.done = false});

  /// The id of the event that added the todo: the same on every peer.
  final EventId id;

  /// What to do.
  final String text;

  /// Whether it is done.
  final bool done;

  /// A copy with the given fields replaced.
  Todo copyWith({String? text, bool? done}) =>
      Todo(id, text ?? this.text, done: done ?? this.done);
}

/// The state of the aggregate: the todos, in order.
final class TodoList {
  /// Creates a list of [todos].
  const TodoList([this.todos = const []]);

  /// The todos, in order.
  final List<Todo> todos;

  /// Where the todo [id] is, or `-1`.
  int indexOf(EventId id) => todos.indexWhere((todo) => todo.id == id);
}
// #enddocregion state

// #docregion events
/// What happens to a [TodoList].
sealed class TodoEvent {
  const TodoEvent();
}

/// Adds a todo at the end.
final class TodoAdded extends TodoEvent {
  /// Creates the event.
  const TodoAdded(this.text);

  /// What to do.
  final String text;
}

/// Replaces the text of [todo].
final class TodoEdited extends TodoEvent {
  /// Creates the event.
  const TodoEdited(this.todo, this.text);

  /// The todo to edit.
  final EventId todo;

  /// The new text.
  final String text;
}

/// Marks [todo] as done, or not.
final class TodoChecked extends TodoEvent {
  /// Creates the event.
  const TodoChecked(this.todo, {required this.done});

  /// The todo to mark.
  final EventId todo;

  /// Whether it is done.
  final bool done;
}

/// Moves [todo] after [after], or first when [after] is `null`.
final class TodoMoved extends TodoEvent {
  /// Creates the event.
  const TodoMoved(this.todo, {this.after});

  /// The todo to move.
  final EventId todo;

  /// The todo it goes after.
  final EventId? after;
}

/// Removes [todo].
final class TodoRemoved extends TodoEvent {
  /// Creates the event.
  const TodoRemoved(this.todo);

  /// The todo to remove.
  final EventId todo;
}

/// Puts back [todo], with its own id, after [after]. An undo writes it.
final class TodoRestored extends TodoEvent {
  /// Creates the event.
  const TodoRestored(this.todo, {this.after});

  /// The todo to put back.
  final Todo todo;

  /// The todo it goes after.
  final EventId? after;
}
// #enddocregion events

// #docregion definition
/// How a [TodoEvent] moves a [TodoList], and how an undo takes it back.
final class TodoListAggregate
    extends InvertibleAggregateDefinition<TodoList, TodoEvent> {
  /// Creates the definition.
  const TodoListAggregate();

  @override
  String get handlerType => 'todo-aggregate';

  @override
  TodoList initial(String id) => const TodoList();

  // Pure: every peer replays the same events, in the same order, through it.
  // An event on a todo that is gone does nothing.
  @override
  TodoList reduce(TodoList state, TodoEvent event, EventContext context) {
    switch (event) {
      case TodoAdded(:final text):
        return TodoList([...state.todos, Todo(context.id, text)]);
      case TodoEdited(:final todo, :final text):
        return _update(state, todo, (found) => found.copyWith(text: text));
      case TodoChecked(:final todo, :final done):
        return _update(state, todo, (found) => found.copyWith(done: done));
      case TodoMoved(:final todo, :final after):
        final index = state.indexOf(todo);
        if (index == -1) {
          return state;
        }
        final todos = [...state.todos];
        return TodoList(_insertAfter(todos, todos.removeAt(index), after));
      case TodoRemoved(:final todo):
        return TodoList([...state.todos.where((found) => found.id != todo)]);
      case TodoRestored(:final todo, :final after):
        if (state.indexOf(todo.id) != -1) {
          return state;
        }
        return TodoList(_insertAfter([...state.todos], todo, after));
    }
  }

  // Read against the state before the event. Ids, never positions: the undo
  // is applied after what the other peers wrote in between.
  @override
  List<TodoEvent> invert(
    TodoList before,
    TodoEvent event,
    EventContext context,
  ) {
    switch (event) {
      case TodoAdded():
        return [TodoRemoved(context.id)];
      case TodoRestored(:final todo):
        return before.indexOf(todo.id) == -1 ? [TodoRemoved(todo.id)] : [];
      case TodoEdited(:final todo) ||
          TodoChecked(:final todo) ||
          TodoMoved(:final todo) ||
          TodoRemoved(:final todo):
        final index = before.indexOf(todo);
        if (index == -1) {
          return [];
        }
        final old = before.todos[index];
        final previous = index == 0 ? null : before.todos[index - 1].id;
        return [
          switch (event) {
            TodoEdited() => TodoEdited(todo, old.text),
            TodoChecked() => TodoChecked(todo, done: old.done),
            TodoMoved() => TodoMoved(todo, after: previous),
            _ => TodoRestored(old, after: previous),
          },
        ];
    }
  }

  @override
  ValueCodec<TodoEvent> get eventCodec => const TodoEventCodec();

  @override
  ValueCodec<TodoList> get stateCodec => const TodoListCodec();

  static TodoList _update(
    TodoList state,
    EventId id,
    Todo Function(Todo todo) change,
  ) {
    final index = state.indexOf(id);
    if (index == -1) {
      return state;
    }
    return TodoList([...state.todos]..[index] = change(state.todos[index]));
  }

  // An anchor that is gone puts the todo first.
  static List<Todo> _insertAfter(List<Todo> todos, Todo todo, EventId? after) {
    final anchor = after == null ? -1 : todos.indexWhere((t) => t.id == after);
    return todos..insert(anchor + 1, todo);
  }
}

/// The kind of the todo list: one spec for the whole app.
final todoListKind = CRDTAggregateHandler.spec(const TodoListAggregate());

/// The todo list of [document].
CRDTAggregateHandler<TodoList, TodoEvent> todosOf(CRDTDocument document) {
  return document.handler(todoListKind, 'todos');
}
// #enddocregion definition

// #docregion codecs
const _json = JsonValueCodec<Map<String, dynamic>>();

String _idToJson(EventId id) => base64Encode(id.toBytes());

EventId _idFromJson(String id) => EventId.fromBytes(base64Decode(id));

Map<String, dynamic> _todoToJson(Todo todo) => {
  'id': _idToJson(todo.id),
  'text': todo.text,
  'done': todo.done,
};

Todo _todoFromJson(Map<String, dynamic> json) => Todo(
  _idFromJson(json['id'] as String),
  json['text'] as String,
  done: json['done'] as bool,
);

/// Writes the events as JSON. The bytes travel and are stored: changing them
/// means a new `version` of the aggregate.
final class TodoEventCodec implements ValueCodec<TodoEvent> {
  /// Creates the codec.
  const TodoEventCodec();

  @override
  Uint8List encode(TodoEvent value) => _json.encode(switch (value) {
    TodoAdded(:final text) => {'type': 'added', 'text': text},
    TodoEdited(:final todo, :final text) => {
      'type': 'edited',
      'todo': _idToJson(todo),
      'text': text,
    },
    TodoChecked(:final todo, :final done) => {
      'type': 'checked',
      'todo': _idToJson(todo),
      'done': done,
    },
    TodoMoved(:final todo, :final after) => {
      'type': 'moved',
      'todo': _idToJson(todo),
      'after': after == null ? null : _idToJson(after),
    },
    TodoRemoved(:final todo) => {'type': 'removed', 'todo': _idToJson(todo)},
    TodoRestored(:final todo, :final after) => {
      'type': 'restored',
      'todo': _todoToJson(todo),
      'after': after == null ? null : _idToJson(after),
    },
  });

  @override
  TodoEvent decode(Uint8List bytes) {
    final json = _json.decode(bytes);
    final after = json['after'] as String?;
    return switch (json['type']) {
      'added' => TodoAdded(json['text'] as String),
      'edited' => TodoEdited(
        _idFromJson(json['todo'] as String),
        json['text'] as String,
      ),
      'checked' => TodoChecked(
        _idFromJson(json['todo'] as String),
        done: json['done'] as bool,
      ),
      'moved' => TodoMoved(
        _idFromJson(json['todo'] as String),
        after: after == null ? null : _idFromJson(after),
      ),
      'removed' => TodoRemoved(_idFromJson(json['todo'] as String)),
      'restored' => TodoRestored(
        _todoFromJson(json['todo'] as Map<String, dynamic>),
        after: after == null ? null : _idFromJson(after),
      ),
      final type => throw FormatException('Unknown todo event: $type'),
    };
  }
}

/// Writes the state as JSON, for snapshots. It keeps the ids: the events
/// written after a snapshot address the todos by them.
final class TodoListCodec implements ValueCodec<TodoList> {
  /// Creates the codec.
  const TodoListCodec();

  @override
  Uint8List encode(TodoList value) =>
      _json.encode({'todos': value.todos.map(_todoToJson).toList()});

  @override
  TodoList decode(Uint8List bytes) => TodoList([
    for (final todo in _json.decode(bytes)['todos'] as List<dynamic>)
      _todoFromJson(todo as Map<String, dynamic>),
  ]);
}

// #enddocregion codecs
