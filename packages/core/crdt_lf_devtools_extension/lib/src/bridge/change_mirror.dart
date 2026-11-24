// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/crdt_lf_client.dart';
import 'package:equatable/equatable.dart';

/// One change of a [ChangeMirror], with its operation envelope.
class MirrorEntry extends Equatable {
  const MirrorEntry({
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

  /// The dependencies of [change]. Read them here: [Change.deps] decodes
  /// them again on each call.
  final List<OperationId> deps;

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
  const MirrorMark._(this._generation, this._length);

  final int _generation;

  final int _length;
}

/// What [ChangeMirror.read] returns.
///
/// `reset` is `true` when `entries` holds every entry of the mirror, and
/// `false` when it holds only the entries added after the read mark.
typedef MirrorRead = ({List<MirrorEntry> entries, bool reset, MirrorMark mark});

/// A local copy of the changes of the document [doc], in replay order.
///
/// It loads only what it misses, and loads again from scratch after a
/// prune.
class ChangeMirror {
  ChangeMirror(this.client, this.doc, {this.pageSize = 1000})
    : _entries = <MirrorEntry>[],
      _ids = <OperationId>{},
      _latest = VersionVector({});

  final CrdtLfClient client;

  /// The tracked id of the document.
  final int doc;

  final int pageSize;

  final List<MirrorEntry> _entries;

  final Set<OperationId> _ids;

  VersionVector _latest;

  int? _pruneEpoch;

  int _changeCount = 0;

  int _generation = 0;

  Future<void> _queue = Future.value();

  List<MirrorEntry> get entries => List.unmodifiable(_entries);

  /// The entries added after [mark], and the mark to read from next.
  ///
  /// With no [mark], after a prune, or when an entry landed before the
  /// entries read at [mark], the read is a reset.
  MirrorRead read([MirrorMark? mark]) {
    final reset = mark == null || mark._generation != _generation;
    return (
      entries: reset ? entries : _entries.sublist(mark._length),
      reset: reset,
      mark: MirrorMark._(_generation, _entries.length),
    );
  }

  int get length => _entries.length;

  /// The prune epoch of the last page; `null` before the first sync.
  int? get pruneEpoch => _pruneEpoch;

  /// The change count of the document at the last page.
  int get changeCount => _changeCount;

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
      _changeCount = page.changeCount;
      for (final bytes in page.changes) {
        _insert(MirrorEntry.decode(bytes));
      }
      onProgress?.call(_entries.length, page.changeCount);
      if (page.done) return;
    }
  }

  void _insert(MirrorEntry entry) {
    final change = entry.change;
    if (!_ids.add(change.id)) return;
    _latest.update(change.author, change.hlc);
    if (_entries.isEmpty ||
        compareChangeOrder(_entries.last.change, change) < 0) {
      _entries.add(entry);
      return;
    }
    _generation++;
    var low = 0;
    var high = _entries.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (compareChangeOrder(_entries[mid].change, change) < 0) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    _entries.insert(low, entry);
  }

  void _clear() {
    _generation++;
    _entries.clear();
    _ids.clear();
    _latest = VersionVector({});
  }
}
