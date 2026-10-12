import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/document/document_events.dart';
import 'package:crdt_lf/src/document/event_outbox.dart';
import 'package:crdt_lf/src/transaction/transaction_manager.dart';
import 'package:test/test.dart';

import '../helpers/handler.dart';

void main() {
  group('DocumentEvents', () {
    test('builds nothing when nobody listens', () {
      final flushed = <TransactionWork>[];
      final events = DocumentEvents(
        outbox: EventOutbox(),
        transactions: TransactionManager(flushWork: flushed.add),
      );
      final doc = CRDTDocument();
      final change =
          doc.createChange(TestOperation.fromHandler(TestHandler(doc)));

      events.reportMove(changes: [change], source: ChangeSource.created);

      expect(events.hasListener, isFalse);
      expect(flushed.single.events, isEmpty);
      expect(flushed.single.otherPendingUpdates, isTrue);
      events.close();
    });
  });
}
