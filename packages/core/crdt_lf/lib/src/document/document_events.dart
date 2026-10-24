// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/document/event_outbox.dart';
import 'package:crdt_lf/src/transaction/transaction_manager.dart';

/// The streams a document reports its moves on, and when an event reaches
/// them.
///
/// With nobody listening, no event is built. Inside a transaction an event
/// waits for the commit, so a listener reads the moves in the order the store
/// made them. Outside one it waits in the [EventOutbox] until the document is
/// settled.
class DocumentEvents {
  /// Creates the streams of a document that publishes through [outbox] and
  /// batches with [transactions].
  DocumentEvents({
    required EventOutbox outbox,
    required TransactionManager transactions,
  })  : _outbox = outbox,
        _transactions = transactions,
        _events = StreamController<CRDTDocumentEvent>.broadcast(),
        _updates = StreamController<void>.broadcast();

  final EventOutbox _outbox;
  final TransactionManager _transactions;
  final StreamController<CRDTDocumentEvent> _events;
  final StreamController<void> _updates;

  /// The moves of the durable state, see [CRDTDocument.events].
  Stream<CRDTDocumentEvent> get events => _events.stream;

  /// The changes the document wrote, in replay order, see
  /// [CRDTDocument.localChanges].
  Stream<Change> get localChanges => _events.stream.expand(
        (event) => event is DocumentChangesApplied &&
                event.source == ChangeSource.created
            ? event.changes.sorted()
            : const <Change>[],
      );

  /// An event each time the document took a change in, see
  /// [CRDTDocument.updates].
  Stream<void> get updates => _updates.stream;

  /// Whether anybody listens to [events].
  bool get hasListener => _events.hasListener;

  /// Publishes [event] on [events], once the document is settled.
  void publish(CRDTDocumentEvent event) {
    if (_events.isClosed || !_events.hasListener) {
      return;
    }
    if (_transactions.queueEvent(event)) {
      return;
    }
    _outbox.add(() {
      if (!_events.isClosed) {
        _events.add(event);
      }
    });
  }

  /// Reports that the document state moved: [changes] reached it from
  /// [source], asked by [origin]. Pass no [changes] for a move that applies
  /// none, such as a snapshot import.
  ///
  /// Inside a transaction the report waits for the commit.
  void reportMove({
    List<Change>? changes,
    ChangeSource? source,
    Object? origin,
  }) {
    // No listener on `events`, so the batch is never read: skip building it
    // and just wake `updates`.
    if (changes == null || changes.isEmpty || !_events.hasListener) {
      _transactions.requestUpdate();
      return;
    }
    _transactions.handleAppliedChanges(
      DocumentChangesApplied(
        changes: changes,
        source: source!,
        origin: origin,
      ),
    );
  }

  /// Wakes [updates].
  void notifyUpdates() => _updates.add(null);

  /// Closes both streams.
  void close() {
    unawaited(_events.close());
    unawaited(_updates.close());
  }
}
