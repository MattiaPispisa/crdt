import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/document/document_events.dart';
import 'package:crdt_lf/src/document/event_outbox.dart';
import 'package:crdt_lf/src/transaction/transaction_manager.dart';
import 'package:test/test.dart';

import '../helpers/handler.dart';

void main() {
  group('DocumentEvents', () {
    late EventOutbox outbox;
    late List<TransactionWork> flushed;
    late TransactionManager transactions;
    late DocumentEvents events;
    late List<CRDTDocumentEvent> received;
    late Change change;

    setUp(() {
      outbox = EventOutbox();
      flushed = [];
      transactions = TransactionManager(flushWork: flushed.add);
      events = DocumentEvents(outbox: outbox, transactions: transactions);
      received = [];
      final doc = CRDTDocument();
      change = doc.createChange(TestOperation.fromHandler(TestHandler(doc)));
    });

    tearDown(() => events.close());

    DocumentChangesApplied applied(ChangeSource source) =>
        DocumentChangesApplied(changes: [change], source: source);

    test('builds nothing when nobody listens', () {
      events.reportMove(changes: [change], source: ChangeSource.created);

      expect(events.hasListener, isFalse);
      expect(flushed.single.events, isEmpty);
      expect(flushed.single.otherPendingUpdates, isTrue);
    });

    test('hands an event out once the outbox flushes', () async {
      events.events.listen(received.add);

      events.publish(applied(ChangeSource.ingested));
      expect(received, isEmpty);

      outbox.flush();
      await Future<void>.delayed(Duration.zero);
      expect(received.single, isA<DocumentChangesApplied>());
    });

    test('holds an event until the transaction commits', () async {
      events.events.listen(received.add);
      final event = applied(ChangeSource.ingested);

      transactions.run(() => events.publish(event));
      outbox.flush();
      await Future<void>.delayed(Duration.zero);

      expect(received, isEmpty);
      expect(flushed.single.events, [event]);
    });

    test('reports a move with the origin that asked for it', () {
      events.events.listen(received.add);

      events.reportMove(
        changes: [change],
        source: ChangeSource.created,
        origin: 'me',
      );

      final reported = flushed.single.events.single as DocumentChangesApplied;
      expect(reported.origin, 'me');
      expect(reported.changes, [change]);
    });

    test('localChanges carries the created changes only', () async {
      final local = <Change>[];
      events.localChanges.listen(local.add);

      events
        ..publish(applied(ChangeSource.ingested))
        ..publish(applied(ChangeSource.created));
      outbox.flush();
      await Future<void>.delayed(Duration.zero);

      expect(local, [change]);
    });

    test('close ends both streams', () async {
      final done = Future.wait([
        events.events.toList(),
        events.updates.toList(),
      ]);

      events.close();

      await done;
    });
  });
}
