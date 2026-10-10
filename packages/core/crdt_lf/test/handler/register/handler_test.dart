import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

import '../conformance/handler_conformance.dart';

final newFlagSpec = CRDTRegisterHandler.spec<bool>('flag');

void main() {
  runHandlerConformanceTests(
    spec: CRDTRegisterHandler.spec<String>('CRDTRegisterHandler<String>'),
    read: (register) => register.value,
    edit: (register, random, token) => register.set(token),
  );

  group('CRDTRegisterHandler', () {
    late CRDTDocument doc;
    late CRDTRegisterHandler<bool> register;

    setUp(() {
      doc = CRDTDocument();
      register = CRDTRegisterHandler<bool>(
        doc,
        'flag',
        handlerType: 'CRDTRegisterHandler<bool>',
      );
    });

    test('is null until set, then holds the value', () {
      expect(register.value, isNull);
      register.set(true);
      expect(register.value, isTrue);
    });

    test('last write wins locally (incremental cache path)', () {
      register
        ..set(true)
        ..set(false);
      expect(register.value, isFalse);
      register.set(true);
      expect(register.value, isTrue);
    });

    test('toString includes the id', () {
      expect(register.toString(), contains('CRDTRegisterHandler'));
    });

    test('resolves as a leaf value inside a ref container', () {
      final nested = CRDTDocument()
        ..register(newFlagSpec)
        ..register(CRDTMapRefHandler.spec)
        ..register(CRDTFugueTextHandler.spec);
      final root = CRDTMapRefHandler(nested, 'root');
      final done = newFlagSpec.create(nested, nested.newHandlerId())..set(true);
      final text = CRDTFugueTextHandler(nested, nested.newHandlerId())
        ..insert(0, 'task');
      root
        ..setRef('text', text)
        ..setRef('done', done);

      expect(root.resolved, {'text': 'task', 'done': true});
    });

    test('the set operation exposes its value via toPayload', () {
      register.set(true);
      final operations = register.operations();
      expect(operations, hasLength(1));
      expect(operations.single.toPayload()['value'], isTrue);
    });

    test('compounds consecutive sets into a single change', () {
      doc.runInTransaction(() {
        register
          ..set(true)
          ..set(false)
          ..set(true);
      });
      expect(register.value, isTrue);
      expect(doc.exportChanges().length, 1);
    });
  });
}
