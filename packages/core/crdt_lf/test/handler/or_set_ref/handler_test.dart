// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

import '../conformance/handler_conformance.dart';

void main() {
  runHandlerConformanceTests(
    spec: CRDTORSetRefHandler.spec,
    // The sorted references, not the raw set: the order every peer reads is
    // part of the contract.
    read: (set) => set.childRefs().toList(),
    edit: (set, random, token) {
      final present = set.value.toList();
      if (present.isEmpty || random.nextBool()) {
        set.add(HandlerRef(token, CRDTFugueTextHandler.spec.type));
      } else {
        set.remove(present[random.nextInt(present.length)]);
      }
    },
  );

  group('CRDTORSetRefHandler', () {
    late CRDTDocument doc;
    late CRDTORSetRefHandler tags;

    setUp(() {
      doc = CRDTDocument();
      tags = CRDTORSetRefHandler(doc, 'tags');
    });

    test('exposes a stable handlerType', () {
      // Pinned to the literal: the tag is a wire value shared across peers.
      expect(tags.handlerType, 'CRDTORSetRefHandler');
    });

    test('addRef/removeRef/containsRef manage the references', () {
      final a = CRDTFugueTextHandler(doc, 'a')..insert(0, 'A');
      final b = CRDTFugueTextHandler(doc, 'b')..insert(0, 'B');
      tags
        ..addRef(b)
        ..addRef(a);

      expect(tags.containsRef(a), isTrue);
      expect(tags.children, [a, b]);
      expect(tags.resolved, ['A', 'B']);

      tags.removeRef(a);

      expect(tags.containsRef(a), isFalse);
      expect(a.isDeleted, isFalse);
      expect(tags.resolved, ['B']);

      // A kind this document does not know resolves to nothing.
      tags.add(const HandlerRef('ghost', 'Unknown'));
      expect(tags.children, [b]);
      expect(tags.resolved, ['B', null]);
      expect(tags.toString(), contains('CRDTORSetRefHandler'));
    });

    test('addChild always adds a new child', () {
      final first = tags.addChild(CRDTFugueTextHandler.spec);
      final second = tags.addChild(CRDTFugueTextHandler.spec);

      expect(first.id, isNot(second.id));
      expect(tags.value, hasLength(2));
    });

    test('removeChild removes the reference and deletes the child', () {
      final child = tags.addChild(CRDTFugueTextHandler.spec)..insert(0, 'x');

      tags.removeChild(child);

      expect(tags.value, isEmpty);
      expect(child.isDeleted, isTrue);
    });
  });
}
