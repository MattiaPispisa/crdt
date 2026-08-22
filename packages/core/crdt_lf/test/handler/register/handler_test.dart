import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

void main() {
  group('CRDTRegisterHandler', () {
    late CRDTDocument doc;
    late CRDTRegisterHandler<bool> register;

    setUp(() {
      doc = CRDTDocument();
      register = CRDTRegisterHandler<bool>(doc, 'flag');
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

    test('handlerType defaults to runtimeType, or a constructor override', () {
      // Default (minification-fragile) tag.
      expect(register.handlerType, 'CRDTRegisterHandler<bool>');
      // A generic handler can be given a stable tag so it keeps working as a
      // nested ref in a dart2js-minified build; the tag flows into HandlerRef.
      final tagged = CRDTRegisterHandler<bool>(
        doc,
        'flag2',
        handlerType: 'register/bool',
      );
      expect(tagged.handlerType, 'register/bool');
      expect(HandlerRef.of(tagged).type, 'register/bool');
    });

    test('concurrent sets converge (last-writer-wins by HLC)', () {
      final docA = CRDTDocument(
        peerId: PeerId.parse('45ee6b65-b393-40b7-9755-8b66dc7d0518'),
      );
      final docB = CRDTDocument(
        peerId: PeerId.parse('a90dfced-cbf0-4a49-9c64-f5b7b62fdc18'),
      );
      final a = CRDTRegisterHandler<int>(docA, 'r');
      final b = CRDTRegisterHandler<int>(docB, 'r');

      a.set(1);
      b.set(2);

      docB.importChanges(docA.exportChanges());
      docA.importChanges(docB.exportChanges());

      // Both peers converge to the same (LWW) value.
      expect(a.value, b.value);
    });

    test('snapshot round-trip preserves a set value', () {
      register.set(true);
      final snapshot = doc.takeSnapshot();

      final docB = CRDTDocument()..importSnapshot(snapshot);
      final registerB = CRDTRegisterHandler<bool>(docB, 'flag');
      expect(registerB.value, isTrue);
    });

    test('snapshot round-trip preserves the unset state', () {
      final snapshot = doc.takeSnapshot();

      final docB = CRDTDocument()..importSnapshot(snapshot);
      final registerB = CRDTRegisterHandler<bool>(docB, 'flag');
      expect(registerB.value, isNull);
    });

    test('resolves as a leaf value inside a ref container', () {
      final nested = CRDTDocument()
        ..registerDefaultFactories()
        ..registerFactory(
          'CRDTRegisterHandler<bool>',
          CRDTRegisterHandler<bool>.new,
        );
      final root = CRDTMapRefHandler(nested, 'root');
      final done = CRDTRegisterHandler<bool>(nested, nested.newHandlerId())
        ..set(true);
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

    test('compacted sets replay identically on a remote peer', () {
      final doc2 = CRDTDocument(peerId: PeerId.generate());
      final register2 = CRDTRegisterHandler<bool>(doc2, 'flag');

      doc.runInTransaction(() {
        register
          ..set(true)
          ..set(false);
      });

      doc2.importChanges(doc.exportChanges());
      expect(register2.value, register.value);
    });
  });
}
