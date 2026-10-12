import 'dart:async';

import 'package:crdt_lf/src/document/event_outbox.dart';
import 'package:test/test.dart';

void main() {
  group('EventOutbox', () {
    late EventOutbox outbox;
    late List<String> delivered;

    setUp(() {
      outbox = EventOutbox();
      delivered = [];
    });

    test('holds events until flush, then hands them out in order', () {
      outbox
        ..add(() => delivered.add('a'))
        ..add(() => delivered.add('b'));
      expect(delivered, isEmpty);

      outbox.flush();

      expect(delivered, ['a', 'b']);
    });

    test('flushes on a microtask when nobody flushes it', () async {
      outbox.add(() => delivered.add('a'));

      await Future<void>.delayed(Duration.zero);

      expect(delivered, ['a']);
    });

    test('hands out, in the same pass, what a listener publishes', () {
      outbox.add(() {
        delivered.add('a');
        outbox
          ..add(() => delivered.add('written back'))
          // Nested: the pass already running picks the event up.
          ..flush();
        delivered.add('a done');
      });

      outbox.flush();

      expect(delivered, ['a', 'a done', 'written back']);
    });

    test('a listener that throws leaves the next events going out', () {
      final errors = <Object>[];

      runZonedGuarded(
        () {
          outbox
            ..add(() => throw StateError('listener'))
            ..add(() => delivered.add('b'))
            ..flush();
        },
        (error, _) => errors.add(error),
      );

      expect(delivered, ['b']);
      expect(errors.single, isA<StateError>());
    });
  });
}
