import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

import '../../helpers/handler.dart';

void main() {
  group('HandlerRef', () {
    test('equality, hashCode and toString', () {
      const a = HandlerRef('id-1', 'CRDTFugueTextHandler');
      const b = HandlerRef('id-1', 'CRDTFugueTextHandler');
      const c = HandlerRef('id-2', 'CRDTFugueTextHandler');

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      // Building a Set exercises both == and hashCode (a and b collapse).
      final refs = <HandlerRef>[a, b, c];
      expect(refs.toSet(), hasLength(2));
      expect(
        a.toString(),
        allOf(contains('CRDTFugueTextHandler'), contains('id-1')),
      );
    });
  });

  group('nestedValueOf', () {
    test('resolves every built-in leaf handler type', () {
      final doc = CRDTDocument();
      final root = CRDTMapRefHandler(doc, 'root');

      final text = CRDTTextHandler(doc, doc.newHandlerId())..insert(0, 'text');
      final list = CRDTListHandler<String>(
        doc,
        doc.newHandlerId(),
        handlerType: 'CRDTListHandler<String>',
      )..insert(0, 'a');
      final fugueList = CRDTFugueListHandler<String>(
        doc,
        doc.newHandlerId(),
        handlerType: 'CRDTFugueListHandler<String>',
      )..insert(0, 'b');
      final movable = CRDTFugueMovableListHandler<String>(
        doc,
        doc.newHandlerId(),
        handlerType: 'CRDTFugueMovableListHandler<String>',
      )..insert(0, 'c');
      final orSet = CRDTORSetHandler<String>(
        doc,
        doc.newHandlerId(),
        handlerType: 'CRDTORSetHandler<String>',
      )..add('x');
      final orMap = CRDTORMapHandler<String, String>(
        doc,
        doc.newHandlerId(),
        handlerType: 'CRDTORMapHandler<String, String>',
      )..put('k', 'v');
      final fugueText = CRDTFugueTextHandler(doc, doc.newHandlerId())
        ..insert(0, 'ft');
      final map = CRDTMapHandler<String>(
        doc,
        doc.newHandlerId(),
        handlerType: 'CRDTMapHandler<String>',
      )..set('m', 'w');

      root
        ..setRef('text', text)
        ..setRef('list', list)
        ..setRef('fugueList', fugueList)
        ..setRef('movable', movable)
        ..setRef('orSet', orSet)
        ..setRef('orMap', orMap)
        ..setRef('fugueText', fugueText)
        ..setRef('map', map);

      expect(root.resolved, {
        'text': 'text',
        'list': ['a'],
        'fugueList': ['b'],
        'movable': ['c'],
        'orSet': {'x'},
        'orMap': {'k': 'v'},
        'fugueText': 'ft',
        'map': {'m': 'w'},
      });
    });

    test('an unrecognized handler type resolves to null', () {
      final doc = CRDTDocument();
      final root = CRDTMapRefHandler(doc, 'root');
      final unknown = TestHandler(doc, id: doc.newHandlerId());
      root.setRef('unknown', unknown);

      expect(root.resolved, {'unknown': null});
    });
  });
}
