import 'package:crdt_lf/crdt_lf.dart';

/// Builds the [Change]s and [Snapshot]s the conformance suite stores.
///
/// Real ones, written by a real document: a store that mangles an operation
/// payload fails here rather than in the app that reads it back.
class ConformanceFixtures {
  /// Creates fixtures for [documentId].
  ConformanceFixtures(String documentId)
      : document = CRDTDocument(documentId: documentId) {
    text = CRDTFugueTextHandler(document, 'text');
    map = CRDTMapHandler<Object>(document, 'map');
  }

  /// The document the fixtures are written by.
  final CRDTDocument document;

  /// A text handler on [document].
  late final CRDTFugueTextHandler text;

  /// A map handler on [document].
  late final CRDTMapHandler<Object> map;

  /// Writes [count] changes and returns them, newest last.
  ///
  /// Emoji on purpose: a store that splits text by code unit corrupts them.
  List<Change> changes(int count) {
    final before = document.exportChanges().length;
    for (var i = 0; i < count; i++) {
      // `text.length`, not `text.value.length`: the text is indexed by rune
      // and 🌍 is two code units, so the string length would overshoot.
      text.insert(text.length, 'a🌍$i');
    }
    final all = document.exportChanges()..sort((a, b) => a.id.compareTo(b.id));
    return all.sublist(before);
  }

  /// Writes a change carrying a nested value, so a store is checked against
  /// more than a flat string.
  Change complexChange() {
    final before = document.exportChanges().length;
    map.set('nested', <String, Object>{
      'list': <Object>[1, 'two', 3.5, true],
      'text': 'ciao 🌍',
    });
    final all = document.exportChanges()..sort((a, b) => a.id.compareTo(b.id));
    return all.sublist(before).single;
  }

  /// A snapshot of the document as it is now.
  Snapshot snapshot() => document.takeSnapshot(pruneHistory: false);

  /// Writes one value through every handler kind, and returns the changes.
  ///
  /// A store keeps opaque bytes, so one handler is usually enough — but a
  /// backend that mangles a payload tends to do it for one shape only.
  List<Change> everyHandler() {
    final before = document.exportChanges().length;

    CRDTListHandler<String>(document, 'list')
      ..insert(0, 'first')
      ..insert(1, 'second');
    CRDTMapHandler<int>(document, 'counts')
      ..set('count', 42)
      ..set('total', 100);
    CRDTTextHandler(document, 'plain').insert(0, 'Hello World');
    CRDTFugueTextHandler(document, 'fugue').insert(0, 'Fugue 🌍');
    CRDTORSetHandler<String>(document, 'set')
      ..add('alpha')
      ..add('beta');
    CRDTORMapHandler<String, int>(document, 'orMap')
      ..put('x', 10)
      ..put('y', 20);

    final all = document.exportChanges()..sort((a, b) => a.id.compareTo(b.id));
    return all.sublist(before);
  }

  /// Checks that [document] reads back what [everyHandler] wrote.
  static void expectEveryHandler(
    CRDTDocument document,
    void Function(Object? actual, Object? expected) check,
  ) {
    check(
      CRDTListHandler<String>(document, 'list').value,
      ['first', 'second'],
    );
    check(
      CRDTMapHandler<int>(document, 'counts').value,
      {'count': 42, 'total': 100},
    );
    check(CRDTTextHandler(document, 'plain').value, 'Hello World');
    check(CRDTFugueTextHandler(document, 'fugue').value, 'Fugue 🌍');
    check(CRDTORSetHandler<String>(document, 'set').value, {'alpha', 'beta'});
    check(
      CRDTORMapHandler<String, int>(document, 'orMap').value,
      {'x': 10, 'y': 20},
    );
  }
}
