// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:convert';

import 'package:crdt_lf/crdt_lf.dart';

/// A piece of a value: some text, or one item, and the peer that wrote it.
typedef TraceToken = ({String text, String? author});

/// Records what each peer reads while a scenario runs on real documents.
final class Trace {
  Trace({required this.kind, required this.peers, required this.read});

  /// How the site draws a value: `text`, `list` or `set`.
  final String kind;

  /// The documents of the scenario, by peer name, in the order to show them.
  final Map<String, CRDTDocument> peers;

  /// What a peer, named by its key in [peers], reads now, as tokens.
  final List<TraceToken> Function(String peer) read;

  final List<Map<String, Object?>> _steps = [];
  final Map<OperationId, ({String author, String label})> _edits = {};
  bool _online = false;

  /// Runs [run], an edit of [peer] that the site names [label].
  void edit(String peer, String label, String caption, void Function() run) {
    final document = peers[peer]!;
    final before = _ids(document);
    run();
    for (final id in _ids(document).difference(before)) {
      _edits[id] = (author: peer, label: label);
    }
    _record(caption, actor: peer, label: label);
  }

  /// Cuts the connection: the edits after it stay on their peer.
  void disconnect(String caption) {
    _online = false;
    _record(caption);
  }

  /// Connects every peer, and sends to each one what it is missing.
  void sync(String caption, {String? why}) {
    _online = true;
    final byId = {
      for (final document in peers.values)
        for (final change in document.exportChanges()) change.id: change,
    };
    final received = <String, List<Map<String, Object?>>>{};
    for (final MapEntry(key: name, value: document) in peers.entries) {
      final own = _ids(document);
      final missing = byId.values.where((change) => !own.contains(change.id));
      final edits = <String, Map<String, Object?>>{};
      for (final change in missing) {
        final edit = _edits[change.id]!;
        final ancestors = _ancestors(change.id, byId);
        final entry = edits.putIfAbsent(
          '${edit.author}/${edit.label}',
          () => {'from': edit.author, 'label': edit.label, 'concurrent': false},
        );
        // The receiver holds a change this edit never saw.
        if (own.any((id) => !ancestors.contains(id))) {
          entry['concurrent'] = true;
        }
      }
      received[name] = edits.values.toList();
    }
    for (final document in peers.values) {
      document.importChanges(byId.values.toList());
    }
    _record(caption, received: received, why: why);
  }

  /// The trace as the site reads it: stable, indented JSON.
  String encode() {
    final json = {'kind': kind, 'peers': peers.keys.toList(), 'steps': _steps};
    return '${const JsonEncoder.withIndent('  ').convert(json)}\n';
  }

  /// Releases the documents of the scenario.
  void dispose() {
    for (final document in peers.values) {
      document.dispose();
    }
  }

  void _record(
    String caption, {
    String? actor,
    String? label,
    Map<String, List<Map<String, Object?>>>? received,
    String? why,
  }) {
    _steps.add({
      'caption': caption,
      if (actor != null) 'actor': actor,
      if (label != null) 'label': label,
      'online': _online,
      'values': {
        for (final name in peers.keys)
          name: [
            for (final token in read(name))
              {'text': token.text, 'author': token.author},
          ],
      },
      if (received != null) 'received': received,
      if (why != null) 'why': why,
    });
  }

  static Set<OperationId> _ids(CRDTDocument document) => {
    for (final change in document.exportChanges()) change.id,
  };

  static Set<OperationId> _ancestors(
    OperationId id,
    Map<OperationId, Change> byId,
  ) {
    final seen = <OperationId>{};
    final stack = [...byId[id]!.deps];
    while (stack.isNotEmpty) {
      final next = stack.removeLast();
      if (seen.add(next)) {
        stack.addAll(byId[next]?.deps ?? const {});
      }
    }
    return seen;
  }
}

/// Joins the characters of [text] into runs, one per author in a row.
List<TraceToken> textTokens(
  CRDTFugueTextHandler text,
  String Function(PeerId author) nameOf,
) {
  final runes = text.value.runes.toList();
  final tokens = <TraceToken>[];
  for (var index = 0; index < runes.length; index++) {
    final author = nameOf(text.nodeAt(index).replicaID);
    final char = String.fromCharCode(runes[index]);
    if (tokens.isNotEmpty && tokens.last.author == author) {
      final last = tokens.removeLast();
      tokens.add((text: last.text + char, author: author));
    } else {
      tokens.add((text: char, author: author));
    }
  }
  return tokens;
}
