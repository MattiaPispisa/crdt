// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf_devtools_extension/src/bridge/models/bridge_event.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/models/json.dart';
import 'package:equatable/equatable.dart';

/// A typed `crdt_lf:devtools:*` event.
sealed class CrdtLfEvent extends Equatable {
  const CrdtLfEvent({required this.time});

  static const String documentsKind = 'crdt_lf:devtools:documents';

  static const String documentKind = 'crdt_lf:devtools:document';

  static const String eventKind = 'crdt_lf:devtools:event';

  static const String deltaKind = 'crdt_lf:devtools:delta';

  /// Parses [event]; `null` for a kind this extension does not know.
  static CrdtLfEvent? fromBridge(BridgeEvent event) => switch (event.kind) {
    documentsKind => DocumentsMoved(time: event.time),
    documentKind => DocumentMoved.fromJson(event.data, event.time),
    eventKind => DocumentLogEvent.fromJson(event.data, event.time),
    deltaKind => HandlerDeltaEvent.fromJson(event.data, event.time),
    _ => null,
  };

  final DateTime time;
}

/// A document was created or disposed.
final class DocumentsMoved extends CrdtLfEvent {
  const DocumentsMoved({required super.time});

  @override
  List<Object?> get props => [time];
}

/// Something moved in the document [doc].
final class DocumentMoved extends CrdtLfEvent {
  const DocumentMoved({
    required super.time,
    required this.doc,
    required this.changes,
    required this.handlers,
    required this.snapshot,
    required this.pruned,
  });

  factory DocumentMoved.fromJson(Json json, DateTime time) => DocumentMoved(
    time: time,
    doc: json.integer('id'),
    changes: json.boolean('changes'),
    handlers: json.boolean('handlers'),
    snapshot: json.boolean('snapshot'),
    pruned: json.boolean('pruned'),
  );

  final int doc;

  final bool changes;

  final bool handlers;

  final bool snapshot;

  final bool pruned;

  @override
  List<Object?> get props => [time, doc, changes, handlers, snapshot, pruned];
}

/// An entry of the event log of a document.
final class DocumentLogEvent extends CrdtLfEvent {
  const DocumentLogEvent({
    required super.time,
    required this.doc,
    required this.n,
    required this.type,
    required this.source,
    required this.reason,
    required this.count,
    required this.ids,
    required this.removed,
    required this.rewritten,
    required this.snapshotId,
    required this.origin,
  });

  factory DocumentLogEvent.fromJson(Json json, DateTime time) =>
      DocumentLogEvent(
        time: time,
        doc: json.integer('doc'),
        n: json.integer('n'),
        type: json.string('type'),
        source: json.stringOrNull('source'),
        reason: json.stringOrNull('reason'),
        count: json.integer('count'),
        ids: json.strings('ids'),
        removed: json.integer('removed'),
        rewritten: json.integer('rewritten'),
        snapshotId: json.stringOrNull('snapshotId'),
        origin: json.stringOrNull('origin'),
      );

  final int doc;

  final int n;

  final String type;

  final String? source;

  final String? reason;

  final int count;

  final List<String> ids;

  final int removed;

  final int rewritten;

  final String? snapshotId;

  final String? origin;

  @override
  List<Object?> get props => [
    time,
    doc,
    n,
    type,
    source,
    reason,
    count,
    ids,
    removed,
    rewritten,
    snapshotId,
    origin,
  ];
}

/// A delta or a reset of a watched handler.
final class HandlerDeltaEvent extends CrdtLfEvent {
  const HandlerDeltaEvent({
    required super.time,
    required this.doc,
    required this.handler,
    required this.seq,
    required this.type,
    required this.cause,
    required this.changeId,
    required this.author,
    required this.local,
    required this.origin,
    required this.empty,
    required this.delta,
  });

  factory HandlerDeltaEvent.fromJson(Json json, DateTime time) =>
      HandlerDeltaEvent(
        time: time,
        doc: json.integer('doc'),
        handler: json.string('handler'),
        seq: json.integer('seq'),
        type: json.string('type'),
        cause: json.stringOrNull('cause'),
        changeId: json.stringOrNull('changeId'),
        author: json.stringOrNull('author'),
        local: json.booleanOrNull('local'),
        origin: json.stringOrNull('origin'),
        empty: json.booleanOrNull('empty'),
        delta: json.stringOrNull('delta'),
      );

  final int doc;

  final String handler;

  final int seq;

  final String type;

  final String? cause;

  final String? changeId;

  final String? author;

  final bool? local;

  final String? origin;

  final bool? empty;

  final String? delta;

  @override
  List<Object?> get props => [
    time,
    doc,
    handler,
    seq,
    type,
    cause,
    changeId,
    author,
    local,
    origin,
    empty,
    delta,
  ];
}
