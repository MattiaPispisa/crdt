// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:convert';
import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/document/document.dart' show DevToolsBridge;
import 'package:hlc_dart/hlc_dart.dart';
import 'package:test/test.dart';

import '../helpers/asset_aggregate.dart';

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

    Map<String, Object?> handlers(CRDTDocument doc) =>
        DevToolsBridge.call('handlers', {'doc': '${trackedId(doc)}'});

    Map<String, Object?> openHandler(CRDTDocument doc, String id) =>
        (handlers(doc)['open']! as List)
            .cast<Map<String, Object?>>()
            .firstWhere((h) => h['id'] == id);

    Object? valueOf(CRDTDocument doc, String id) => DevToolsBridge.call(
          'handlerValue',
          {'doc': '${trackedId(doc)}', 'handler': id},
        )['value'];

    test('handlers lists a container with its children', () {
      final doc = CRDTDocument();
      final text = CRDTTextHandler(doc, 'text')..insert(0, 'a');
      CRDTMapRefHandler(doc, 'root').setRef('child', text);

      final root = openHandler(doc, 'root');
      expect(root['container'], isTrue);
      expect(root['children'], [
        {'id': 'text', 'type': text.handlerType},
      ]);
      expect(root['changeCount'], 1);
      expect(root['cache'], 'warm');

      final child = openHandler(doc, 'text');
      expect(child, {
        'id': 'text',
        'type': text.handlerType,
        'container': false,
        'children': <Object?>[],
        'changeCount': 1,
        'revision': doc.revisionForHandler('text'),
        'cache': child['cache'],
        'pendingRemote': 0,
        'deltas': true,
        'watched': false,
        'deltaSeq': 0,
        'invertible': text.invertible,
        'undoTracked': false,
        'snapshotBytes': null,
      });
    });

    test('handlers moves a deleted handler to deleted', () {
      final doc = CRDTDocument();
      final text = CRDTTextHandler(doc, 'text')..insert(0, 'a');
      doc.deleteHandler(text);

      final result = handlers(doc);
      expect(result['open'], isEmpty);
      expect(result['closed'], isEmpty);
      expect(result['deleted'], ['text']);
    });

    test('handlers lists a handler with changes and no instance as closed', () {
      final source = CRDTDocument();
      final text = CRDTTextHandler(source, 'text')..insert(0, 'a');
      final doc = CRDTDocument()..importChanges(source.exportChanges());

      expect(handlers(doc)['closed'], [
        {'id': 'text', 'type': text.handlerType, 'changeCount': 1},
      ]);

      // A container makes the snapshot carry its handler manifest.
      CRDTMapRefHandler(source, 'root').setRef('child', text);
      source.takeSnapshot();
      final restored = CRDTDocument()..importSnapshot(source.snapshot!);
      expect(handlers(restored)['closed'], [
        {'id': 'text', 'type': text.handlerType, 'changeCount': 0},
        {'id': 'root', 'type': 'CRDTMapRefHandler', 'changeCount': 0},
      ]);
    });

    test('the cache is none before a read and warm after', () {
      final source = CRDTDocument();
      CRDTTextHandler(source, 'text').insert(0, 'a');
      final doc = CRDTDocument()..importChanges(source.exportChanges());
      final text = CRDTTextHandler(doc, 'text');

      expect(openHandler(doc, 'text')['cache'], 'none');
      expect(openHandler(doc, 'text')['cache'], 'none');
      expect(text.value, 'a');
      expect(openHandler(doc, 'text')['cache'], 'warm');
    });

    test('handlerValue encodes the value of each handler kind', () {
      final doc = CRDTDocument();
      CRDTTextHandler(doc, 'text').insert(0, 'ab');
      CRDTFugueTextHandler(doc, 'fugue-text').insert(0, 'cd');
      CRDTListHandler<int>(doc, 'list', handlerType: 'list').insert(0, 1);
      CRDTFugueListHandler<int>(doc, 'fugue-list', handlerType: 'fl')
          .insert(0, 2);
      CRDTFugueMovableListHandler<int>(doc, 'movable', handlerType: 'mv')
          .insert(0, 3);
      CRDTMapHandler<int>(doc, 'map', handlerType: 'map').set('k', 4);
      CRDTRegisterHandler<int>(doc, 'register', handlerType: 'register').set(5);
      CRDTORSetHandler<int>(doc, 'or-set', handlerType: 'or-set').add(6);
      CRDTORMapHandler<String, int>(doc, 'or-map', handlerType: 'om')
          .put('k', 7);
      CRDTFugueRichTextHandler(doc, 'rich').insert(0, 'hi');
      final asset = doc.handler(
        CRDTAggregateHandler.spec(const AssetAggregate()),
        'asset',
      );
      CRDTListRefHandler(doc, 'refs').insertRef(0, asset);

      // The kind, the length and the single item of a one-item collection.
      List<Object?> one(String kind, Object? item) => [kind, 1, item];
      List<Object?> shape(Object? node) {
        final map = node! as Map;
        return [map[r'$t'], map['length'], (map['items'] as List?)?.single];
      }

      expect(valueOf(doc, 'text'), 'ab');
      expect(valueOf(doc, 'fugue-text'), 'cd');
      expect(shape(valueOf(doc, 'list')), one('list', 1));
      expect(shape(valueOf(doc, 'fugue-list')), one('list', 2));
      expect(shape(valueOf(doc, 'movable')), one('list', 3));
      expect((valueOf(doc, 'map')! as Map)['entries'], [
        ['k', 4],
      ]);
      expect(valueOf(doc, 'register'), 5);
      expect(shape(valueOf(doc, 'or-set')), one('set', 6));
      expect((valueOf(doc, 'or-map')! as Map)['entries'], [
        ['k', 7],
      ]);
      expect(
        (shape(valueOf(doc, 'rich'))[2]! as Map)['text'],
        'hi',
      );
      expect((valueOf(doc, 'asset')! as Map)[r'$t'], 'object');
      expect(
        shape(valueOf(doc, 'refs')),
        one('list', {r'$t': 'ref', 'id': 'asset', 'type': asset.handlerType}),
      );
    });

    test('handlerValue applies the limits and checks its parameters', () {
      final doc = CRDTDocument();
      CRDTTextHandler(doc, 'text').insert(0, 'abcdef');
      final id = '${trackedId(doc)}';

      final result = DevToolsBridge.call('handlerValue', {
        'doc': id,
        'handler': 'text',
        'maxString': '2',
      });
      expect(result, {
        'id': 'text',
        'type': doc.handlerById('text')!.handlerType,
        'revision': doc.revisionForHandler('text'),
        'value': {r'$t': 'string', 'length': 6, 'head': 'ab'},
      });

      for (final params in [
        {'doc': id},
        {'doc': id, 'handler': 'missing'},
        {'doc': id, 'handler': 'text', 'maxItems': 'x'},
        {'doc': id, 'handler': 'text', 'maxDepth': '-1'},
      ]) {
        expect(
          () => DevToolsBridge.call('handlerValue', params),
          throwsArgumentError,
        );
      }
    });

    List<Change> decode(Map<String, Object?> page) => [
          for (final raw in page['changes']! as List)
            Change.fromBytes(base64Decode(raw as String)),
        ];

    // The highest clock per author: what a caller sends as the next `since`.
    String sinceOf(List<Change> changes) => base64Encode(
          VersionVector({
            for (final change in changes) change.author: change.hlc,
          }).toBytes(),
        );

    test('changes pages through the log with limit and since', () {
      final doc = CRDTDocument();
      final text = CRDTTextHandler(doc, 'text');
      for (var i = 0; i < 5; i++) {
        text.insert(i, 'x');
      }
      final id = '${trackedId(doc)}';

      final first = DevToolsBridge.call('changes', {'doc': id, 'limit': '2'});
      expect(first['done'], isFalse);
      expect(first['changeCount'], 5);
      final held = decode(first);
      expect(held, hasLength(2));

      while (true) {
        final page = DevToolsBridge.call(
          'changes',
          {'doc': id, 'limit': '2', 'since': sinceOf(held)},
        );
        held.addAll(decode(page));
        if (page['done']! as bool) break;
      }
      expect(held, doc.exportChanges().sorted());
    });

    test('changes come in the replay order of two peers', () {
      final a = CRDTDocument(peerId: PeerId.generate());
      final b = CRDTDocument(peerId: PeerId.generate());
      final textA = CRDTTextHandler(a, 'text');
      final textB = CRDTTextHandler(b, 'text');
      for (var i = 0; i < 3; i++) {
        textA.insert(0, 'a');
        textB.insert(0, 'b');
      }
      a.importChanges(b.exportChanges());

      final changes =
          decode(DevToolsBridge.call('changes', {'doc': '${trackedId(a)}'}));
      expect(changes, hasLength(6));
      expect(changes, [...changes]..sort(compareChangeOrder));
      expect(changes.map((c) => c.author).toSet(), {a.peerId, b.peerId});
    });

    test('changes drops the pruned changes and moves pruneEpoch', () {
      final doc = CRDTDocument();
      CRDTTextHandler(doc, 'text').insert(0, 'a');
      doc.takeSnapshot();

      final page = DevToolsBridge.call('changes', {'doc': '${trackedId(doc)}'});
      expect(page, {
        'pruneEpoch': 1,
        'changeCount': 0,
        'done': true,
        'changes': <String>[],
      });
    });

    test('changes and operation check their parameters', () {
      final doc = CRDTDocument();
      final id = '${trackedId(doc)}';
      for (final (method, params) in [
        ('changes', {'doc': id, 'since': '%'}),
        (
          'changes',
          {
            'doc': id,
            'since': base64Encode([1]),
          }
        ),
        ('operation', {'doc': id}),
        (
          'operation',
          {
            'doc': id,
            'change': base64Encode([0]),
          }
        ),
      ]) {
        expect(() => DevToolsBridge.call(method, params), throwsArgumentError);
      }
    });

    test('operation decodes a change of an open handler', () {
      final doc = CRDTDocument();
      final text = CRDTTextHandler(doc, 'text')..insert(0, 'hi');
      final change = doc.exportChanges().single;

      final result = DevToolsBridge.call('operation', {
        'doc': '${trackedId(doc)}',
        'change': base64Encode(change.toBytes()),
      });
      expect(result, {
        'changeId': change.id.toString(),
        'handlerId': 'text',
        'handlerType': text.handlerType,
        'kind': OperationType.kindInsert,
        'stamped': false,
        'open': true,
        'payload': {
          r'$t': 'map',
          'length': 5,
          'entries': [
            ['id', 'text'],
            ['type', text.insertType.toPayload()],
            ['stamp', change.id.toString()],
            ['index', 0],
            ['text', 'hi'],
          ],
        },
        'error': null,
      });
    });

    test('operation leaves a change of a closed handler undecoded', () {
      final source = CRDTDocument();
      CRDTTextHandler(source, 'text').insert(0, 'hi');
      final doc = CRDTDocument()..importChanges(source.exportChanges());
      final change = doc.exportChanges().single;

      final result = DevToolsBridge.call('operation', {
        'doc': '${trackedId(doc)}',
        'change': base64Encode(change.toBytes()),
      });
      expect(result, containsPair('handlerId', 'text'));
      expect(result, containsPair('open', false));
      expect(result, containsPair('payload', null));
      expect(result, containsPair('error', null));
    });

    test('operation reports a body it cannot decode', () {
      final doc = CRDTDocument();
      final text = CRDTTextHandler(doc, 'text');
      final change = Change.fromPayloadBytes(
        id: OperationId(doc.peerId, HybridLogicalClock(l: 1, c: 0)),
        deps: {},
        author: doc.peerId,
        payloadBytes: OperationEnvelopeCodec.encode(
          handlerType: text.handlerType,
          handlerId: text.id,
          kind: OperationType.kindInsert,
          body: Uint8List.fromList([0xFF]),
        ),
      );

      final result = DevToolsBridge.call('operation', {
        'doc': '${trackedId(doc)}',
        'change': base64Encode(change.toBytes()),
      });
      expect(result, containsPair('handlerId', 'text'));
      expect(result, containsPair('payload', null));
      expect(result['error'], isA<String>());
    });
  });
}
