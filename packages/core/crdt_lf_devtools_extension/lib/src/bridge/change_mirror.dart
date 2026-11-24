// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/crdt_lf_client.dart';
import 'package:equatable/equatable.dart';

/// One change of a [ChangeMirror], with its operation envelope.
class MirrorEntry extends Equatable {
  MirrorEntry({
    required this.change,
    required this.bytes,
    required this.deps,
    required this.handlerId,
    required this.handlerType,
    required this.kind,
    required this.stamped,
  });

  /// Decodes the [Change.toBytes] [bytes]; the envelope fields are `null`
  /// when the envelope is not readable.
  factory MirrorEntry.decode(Uint8List bytes) {
    final change = Change.fromBytes(bytes);
    final deps = List<OperationId>.unmodifiable(change.deps);
    try {
      final envelope = OperationEnvelopeCodec.decode(change.payloadBytes());
      return MirrorEntry(
        change: change,
        bytes: bytes,
        deps: deps,
        handlerId: envelope.handlerId,
        handlerType: envelope.handlerType,
        kind: envelope.kind,
        stamped: envelope.stamped,
      );
    } on FormatException {
      return MirrorEntry(
        change: change,
        bytes: bytes,
        deps: deps,
        handlerId: null,
        handlerType: null,
        kind: null,
        stamped: null,
      );
    }
  }

  final Change change;

  final Uint8List bytes;

  /// The dependencies of [change].
  // Kept: `Change.deps` decodes them again on each call.
  final List<OperationId> deps;

  /// The id of [change] in lower case, for the id filter.
  // Late: a load that filters nothing builds no string.
  late final String idText = change.id.toString().toLowerCase();

  final String? handlerId;

  final String? handlerType;

  final int? kind;

  final bool? stamped;

  int get byteLength => bytes.length;

  @override
  List<Object?> get props => [change.id, handlerId, handlerType, kind, stamped];
}

/// Where a reader of a [ChangeMirror] stopped; see [ChangeMirror.read].
class MirrorMark {
  const MirrorMark._(this._rewrites, this._length);

  final int _rewrites;

  final int _length;
}

/// What [ChangeMirror.read] returns.
///
/// The reader keeps its first `from` entries and puts `entries` after them.
typedef MirrorRead = ({List<MirrorEntry> entries, int from, MirrorMark mark});

/// A local copy of the changes of the document [doc], in replay order.
///
/// It loads only what it misses, and loads again from scratch after a
/// prune.
class ChangeMirror {
  ChangeMirror(this.client, this.doc, {this.pageSize = 1000})
    : _entries = <MirrorEntry>[],
      _ids = <OperationId>{},
      _latest = VersionVector({}),
      _rewrites = <int>[];

  final CrdtLfClient client;

  /// The tracked id of the document.
  final int doc;

  final int pageSize;

  final List<MirrorEntry> _entries;

  final Set<OperationId> _ids;

  VersionVector _latest;

  int? _pruneEpoch;

  // For each page merged before the last entry and each prune, the first
  // index it moved.
  final List<int> _rewrites;

  Future<void> _queue = Future.value();

  /// What moved since [mark], and the mark to read from next.
  ///
  /// With no [mark], `from` is 0 and `entries` holds every entry.
  MirrorRead read([MirrorMark? mark]) {
    var from = mark?._length ?? 0;
    for (
      var i = mark?._rewrites ?? _rewrites.length;
      i < _rewrites.length;
      i++
    ) {
      if (_rewrites[i] < from) from = _rewrites[i];
    }
    return (
      entries: _entries.sublist(from),
      from: from,
      mark: MirrorMark._(_rewrites.length, _entries.length),
    );
  }

  int get length => _entries.length;

  /// Loads the changes the mirror misses, page by page.
  ///
  /// [onProgress] gets the entries held and the document total after each
  /// page. Calls run one after the other.
  Future<void> sync({void Function(int loaded, int total)? onProgress}) {
    // Two syncs at once would both page from the same `since`.
    final next = _queue.then((_) => _sync(onProgress));
    _queue = next.then((_) {}, onError: (Object _) {});
    return next;
  }

  Future<void> _sync(void Function(int loaded, int total)? onProgress) async {
    while (true) {
      final page = await client.changes(doc, since: _latest, limit: pageSize);
      if (_pruneEpoch != null && page.pruneEpoch != _pruneEpoch) {
        _clear();
        _pruneEpoch = page.pruneEpoch;
        continue;
      }
      _pruneEpoch = page.pruneEpoch;
      _merge([
        for (final bytes in page.changes)
          if (MirrorEntry.decode(bytes) case final entry
              when _ids.add(entry.change.id))
            entry,
      ]);
      onProgress?.call(_entries.length, page.changeCount);
      if (page.done) return;
    }
  }

  // One pass per page: inserting older changes one by one shifts the tail
  // each time.
  void _merge(List<MirrorEntry> added) {
    if (added.isEmpty) return;
    assert(
      [
        for (var i = 1; i < added.length; i++)
          compareChangeOrder(added[i - 1].change, added[i].change) < 0,
      ].every((ordered) => ordered),
      'The app sends a page in replay order',
    );
    for (final entry in added) {
      _latest.update(entry.change.author, entry.change.hlc);
    }
    if (_entries.isEmpty ||
        compareChangeOrder(_entries.last.change, added.first.change) < 0) {
      _entries.addAll(added);
      return;
    }
    var first = 0;
    var high = _entries.length;
    while (first < high) {
      final mid = (first + high) >> 1;
      if (compareChangeOrder(_entries[mid].change, added.first.change) < 0) {
        first = mid + 1;
      } else {
        high = mid;
      }
    }
    final tail = _entries.sublist(first);
    _entries.length = first;
    var i = 0;
    var j = 0;
    while (i < tail.length && j < added.length) {
      _entries.add(
        compareChangeOrder(tail[i].change, added[j].change) < 0
            ? tail[i++]
            : added[j++],
      );
    }
    _entries
      ..addAll(tail.skip(i))
      ..addAll(added.skip(j));
    _rewrites.add(first);
  }

  void _clear() {
    _rewrites.add(0);
    _entries.clear();
    _ids.clear();
    _latest = VersionVector({});
  }
}
