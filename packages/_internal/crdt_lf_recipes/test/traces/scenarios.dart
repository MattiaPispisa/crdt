// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';

import 'trace.dart';

// Pinned: concurrent inserts at one spot sort by peer id, so the golden files
// depend on them.
final _alice = PeerId.parse('00000000-0000-4000-8000-00000000000a');
final _bob = PeerId.parse('00000000-0000-4000-8000-00000000000b');

Map<String, CRDTDocument> _peers() => {
  'Alice': CRDTDocument(peerId: _alice),
  'Bob': CRDTDocument(peerId: _bob),
};

String _nameOf(PeerId author) => author == _alice ? 'Alice' : 'Bob';

/// Every scenario the site shows, by trace id.
final Map<String, Future<Trace> Function()> scenarios = {
  'fugue-same-spot': _fugueSameSpot,
  'or-add-remove': _orAddRemove,
  'move-concurrent': _moveConcurrent,
};

Future<Trace> _fugueSameSpot() async {
  final peers = _peers();
  final texts = {
    for (final MapEntry(:key, :value) in peers.entries)
      key: CRDTFugueTextHandler(value, 'note'),
  };
  final trace =
      Trace(
          id: 'fugue-same-spot',
          kind: 'text',
          peers: peers,
          read: (peer) => textTokens(texts[peer]!, _nameOf),
        )
        ..edit(
          'Alice',
          'insert "Hello"',
          'Alice writes "Hello".',
          () => texts['Alice']!.insert(0, 'Hello'),
        )
        ..sync('They sync: Bob reads "Hello" too.')
        ..disconnect('Both go offline.')
        ..edit(
          'Alice',
          'insert " World" after "Hello"',
          'Alice adds " World" at the end.',
          () => texts['Alice']!.insert(5, ' World'),
        )
        ..edit(
          'Bob',
          'insert " Dart" after "Hello"',
          'Bob adds " Dart" at the same spot.',
          () => texts['Bob']!.insert(5, ' Dart'),
        )
        ..sync(
          'They meet again, and each one receives the insert of the other.',
          why:
              'The two inserts are concurrent, at the same spot. Each one '
              'stays whole, and the peer ids pick the order: the id of Alice '
              'sorts first, so " World" comes first on both peers.',
        );
  return trace;
}

Future<Trace> _orAddRemove() async {
  final peers = _peers();
  final tags = {
    for (final MapEntry(:key, :value) in peers.entries)
      key: CRDTORSetHandler<String>(value, 'tags', handlerType: 'task-tags'),
  };
  final trace =
      Trace(
          id: 'or-add-remove',
          kind: 'set',
          peers: peers,
          read:
              (peer) => [
                for (final tag in tags[peer]!.value.toList()..sort())
                  (text: tag, author: null),
              ],
        )
        ..edit(
          'Alice',
          'add "urgent"',
          'Alice tags the task "urgent".',
          () => tags['Alice']!.add('urgent'),
        )
        ..sync('They sync: Bob sees the tag too.')
        ..disconnect('Both go offline.')
        ..edit(
          'Alice',
          'remove "urgent"',
          'Alice removes "urgent".',
          () => tags['Alice']!.remove('urgent'),
        )
        ..edit(
          'Bob',
          'add "urgent"',
          'Bob adds "urgent" again: the deadline moved.',
          () => tags['Bob']!.add('urgent'),
        )
        ..sync(
          'They meet again, and each one receives the edit of the other.',
          why:
              'The remove and the add are concurrent. The remove of Alice '
              'deletes only the tag she saw. The add of Bob made a new tag '
              'she never saw, so the add wins: "urgent" stays on both peers.',
        );
  return trace;
}

Future<Trace> _moveConcurrent() async {
  final peers = _peers();
  final lists = {
    for (final MapEntry(:key, :value) in peers.entries)
      key: CRDTFugueMovableListHandler<String>(
        value,
        'todos',
        handlerType: 'todo-list',
      ),
  };
  final trace =
      Trace(
          id: 'move-concurrent',
          kind: 'list',
          peers: peers,
          read:
              (peer) => [
                for (final item in lists[peer]!.value)
                  (text: item, author: null),
              ],
        )
        ..edit(
          'Alice',
          'insert three todos',
          'Alice writes three todos.',
          () => lists['Alice']!.insertAll(0, [
            'Buy milk',
            'Call Ada',
            'Book flights',
          ]),
        )
        ..sync('They sync: Bob reads the same list.')
        ..disconnect('Both go offline.')
        ..edit(
          'Alice',
          'move "Book flights" to the top',
          'Alice moves "Book flights" to the top.',
          () => lists['Alice']!.move(2, 0),
        );
  // The later move wins: a pause makes Bob's clock read later than Alice's.
  await Future<void>.delayed(const Duration(milliseconds: 5));
  trace
    ..edit(
      'Bob',
      'move "Book flights" to the middle',
      'A moment later, Bob moves "Book flights" to the middle.',
      () => lists['Bob']!.move(2, 1),
    )
    ..sync(
      'They meet again, and each one receives the move of the other.',
      why:
          'Both moved the same item. It keeps one identity, so it lands in '
          'one place: the later move wins, on both peers. Nothing is '
          'duplicated.',
    );
  return trace;
}
