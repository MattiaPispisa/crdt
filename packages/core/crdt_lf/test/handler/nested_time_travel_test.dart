import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

void main() {
  group('nested time-travel', () {
    test('resolved subtree reflects the history cursor position', () {
      final doc = CRDTDocument()..registerDefaultFactories();
      final title = CRDTFugueTextHandler(doc, 'title');
      CRDTMapRefHandler(doc, 'root').setRef('title', title); // change 1
      title
        ..insert(0, 'A') // change 2
        ..insert(1, 'B'); // change 3

      final session = doc.toTimeTravel();
      final viewRoot =
          session.getHandler<CRDTMapRefHandler, Map<String, HandlerRef>>(
        (d) => CRDTMapRefHandler(d, 'root'),
      );

      expect(session.length, 3);
      expect(viewRoot.resolved, {'title': 'AB'});

      session.previous();
      expect(viewRoot.resolved, {'title': 'A'});

      session.previous();
      expect(viewRoot.resolved, {'title': ''});

      session.jump(0);
      expect(viewRoot.resolved, <String, Object?>{});

      session.jump(3);
      expect(viewRoot.resolved, {'title': 'AB'});

      session.dispose();
    });
  });
}
