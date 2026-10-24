// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

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

    test('flushes on a microtask when nobody flushes it', () async {
      outbox.add(() => delivered.add('a'));

      await Future<void>.delayed(Duration.zero);

      expect(delivered, ['a']);
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
