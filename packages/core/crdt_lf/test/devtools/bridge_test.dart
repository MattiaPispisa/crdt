// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/document/document.dart' show DevToolsBridge;
import 'package:test/test.dart';

void main() {
  group('DevToolsBridge', () {
    late List<(String, Map<String, Object?>)> events;

    setUp(() {
      DevToolsBridge.reset();
      events = [];
      DevToolsBridge.onEvent = (kind, data) => events.add((kind, data));
    });

    tearDown(() {
      DevToolsBridge.onEvent = null;
      DevToolsBridge.reset();
    });

    List<Map<String, Object?>> documents() =>
        (DevToolsBridge.call('documents', {})['documents']! as List)
            .cast<Map<String, Object?>>();

    int trackedId(CRDTDocument doc) =>
        documents().firstWhere((d) => d['documentId'] == doc.documentId)['id']!
            as int;

    test('lists a new document and drops a disposed one', () {
      final kept = CRDTDocument(documentId: 'kept');
      final disposed = CRDTDocument(documentId: 'disposed');
      expect(
        documents().map((d) => d['documentId']),
        ['kept', 'disposed'],
      );

      disposed.dispose();
      expect(documents().map((d) => d['documentId']), ['kept']);
      expect(DevToolsBridge.call('documents', {})['protocol'], 1);
      kept.dispose();
    });

    test('summarizes a document', () {
      final peer = PeerId.parse('45ee6b65-b393-40b7-9755-8b66dc7d0518');
      final doc = CRDTDocument(peerId: peer, documentId: 'doc');
      CRDTTextHandler(doc, 'text')
        ..insert(0, 'a')
        ..insert(1, 'b');
      CRDTListHandler<int>(doc, 'list', handlerType: 'int-list');

      final summary = documents().single;
      expect(summary, {
        'id': summary['id'],
        'documentId': 'doc',
        'peerId': peer.toString(),
        'hlc': doc.hlc.toString(),
        'changeCount': 2,
        'handlerCount': 2,
        'frontiers': [for (final id in doc.version) id.toString()],
        'versionVector': {
          peer.toString(): doc.version.single.hlc.toString(),
        },
        'snapshotId': null,
        'pruneEpoch': 0,
        'undoManagers': 0,
        'recording': false,
      });
    });

    test('document adds the undo managers and the capabilities', () {
      final doc = CRDTDocument();
      final text = CRDTFugueTextHandler(doc, 'text');
      CRDTUndoManager(
        doc,
        trackedOrigins: {#editor},
        captureTimeout: Duration.zero,
        stackLimit: 10,
      ).track(text);
      doc.runInTransaction(() => text.insert(0, 'hi'), origin: #editor);

      final detail = DevToolsBridge.call('document', {
        'doc': '${trackedId(doc)}',
      });
      expect(detail['undoManagers'], 1);
      expect(detail['undo'], [
        {
          'canUndo': true,
          'canRedo': false,
          'undoDepth': 1,
          'redoDepth': 0,
          'tracked': ['text'],
          'stackLimit': 10,
          'captureTimeoutMs': 0,
          'trackedOrigins': 1,
        },
      ]);
      final capabilities = detail['capabilities']! as Map<String, Object?>;
      expect(
        capabilities[text.handlerType],
        doc.describeBuildCapabilities()[text.handlerType].toString(),
      );
    });

    test('throws ArgumentError for a bad document or method', () {
      final doc = CRDTDocument();
      final id = trackedId(doc);
      doc.dispose();

      for (final params in [
        <String, String>{},
        {'doc': 'x'},
        {'doc': '$id'},
      ]) {
        expect(
          () => DevToolsBridge.call('document', params),
          throwsArgumentError,
        );
      }
      expect(() => DevToolsBridge.call('nope', {}), throwsArgumentError);
    });

    test('coalesces a burst of writes into one document event', () async {
      final doc = CRDTDocument();
      final text = CRDTTextHandler(doc, 'text');
      await Future<void>.microtask(() {});
      expect(events.map((e) => e.$1), [
        'crdt_lf:devtools:documents',
        'crdt_lf:devtools:document',
      ]);
      events.clear();

      for (var i = 0; i < 100; i++) {
        text.insert(i, 'x');
      }
      await Future<void>.microtask(() {});

      final (kind, data) = events.single;
      expect(kind, 'crdt_lf:devtools:document');
      expect(data, {
        'id': trackedId(doc),
        'changes': true,
        'handlers': false,
        'snapshot': false,
        'pruned': false,
      });
    });

    test('a prune increments pruneEpoch', () async {
      final doc = CRDTDocument();
      CRDTTextHandler(doc, 'text').insert(0, 'a');
      await Future<void>.microtask(() {});
      events.clear();

      final snapshot = doc.takeSnapshot();
      final summary = documents().single;
      expect(summary['pruneEpoch'], 1);
      expect(summary['snapshotId'], snapshot.id);

      await Future<void>.microtask(() {});
      expect(events.single.$2, containsPair('snapshot', true));
      expect(events.single.$2, containsPair('pruned', true));
    });

    test('posts nothing without a receiver', () async {
      DevToolsBridge.onEvent = null;
      final doc = CRDTDocument();
      CRDTTextHandler(doc, 'text').insert(0, 'a');
      doc.takeSnapshot();
      await Future<void>.microtask(() {});

      expect(events, isEmpty);
      expect(documents().single['pruneEpoch'], 1);
    });
  });
}
