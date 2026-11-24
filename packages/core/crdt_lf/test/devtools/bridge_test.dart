// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/document/document.dart' show DevToolsBridge;
import 'package:hlc_dart/hlc_dart.dart';
import 'package:test/test.dart';

import '../helpers/asset_aggregate.dart';
import '../helpers/pn_counter_handler.dart';

void main() {
  group('DevToolsBridge', () {
    late List<(String, Map<String, Object?>)> events;
    final lease = DevToolsBridge.lease;

    setUp(() {
      DevToolsBridge.reset();
      events = [];
      DevToolsBridge.onEvent = (kind, data) => events.add((kind, data));
    });

    tearDown(() {
      DevToolsBridge.onEvent = null;
      DevToolsBridge.lease = lease;
      DevToolsBridge.reset();
    });

    List<Map<String, Object?>> documents() =>
        (DevToolsBridge.call('documents', {})['documents']! as List)
            .cast<Map<String, Object?>>();

    List<Map<String, Object?>> posted(String kind) => [
          for (final (k, data) in events)
            if (k == kind) data,
        ];

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

      final id = '${trackedId(disposed)}';
      final one = DevToolsBridge.call('documents', {'doc': id});
      expect(one['documents'], [documents().last]);

      disposed.dispose();
      expect(documents().map((d) => d['documentId']), ['kept']);
      expect(DevToolsBridge.call('documents', {})['protocol'], 1);
      expect(
        () => DevToolsBridge.call('documents', {'doc': id}),
        throwsArgumentError,
      );
      kept.dispose();
    });

    test(
      'drops a document collected without dispose, even when watched',
      () async {
        // A function, so no local of the test holds the document.
        WeakReference<CRDTDocument> openAndDrop() {
          final doc = CRDTDocument();
          final text = CRDTTextHandler(doc, 'text')..insert(0, 'a');
          expect(text.value, 'a');
          final params = {'doc': '${trackedId(doc)}', 'handler': 'text'};
          DevToolsBridge.call('watchStart', params);
          DevToolsBridge.call('eventsStart', params);
          DevToolsBridge.call('historyOpen', params);
          return WeakReference(doc);
        }

        final dropped = openAndDrop();
        await pumpEventQueue();
        final stop = DateTime.now().add(const Duration(seconds: 20));
        final garbage = <List<Object>>[];
        while (dropped.target != null) {
          if (DateTime.now().isAfter(stop)) fail('The document stays alive');
          garbage.add(List<Object>.generate(30000, (_) => Object()));
          if (garbage.length > 50) garbage.removeAt(0);
          await Future<void>.delayed(Duration.zero);
        }
        await pumpEventQueue();
        expect(documents(), isEmpty);
      },
      testOn: 'vm',
    );

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
        'debugName': null,
        'handlerNames': <String, String>{},
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

    test('a debug name shows in the summary and posts documents', () async {
      final doc = CRDTDocument(debugName: 'notes');
      CRDTTextHandler(doc, 'text').debugName = 'title';
      expect(documents().single['debugName'], 'notes');
      expect(documents().single['handlerNames'], {'text': 'title'});
      await Future<void>.microtask(() {});
      events.clear();

      doc.debugName = 'renamed';
      await Future<void>.microtask(() {});
      expect(events.map((e) => e.$1), ['crdt_lf:devtools:documents']);
      expect(documents().single['debugName'], 'renamed');
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
      expect(root['cache'], 'none');

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

      final snapshot = source.snapshot!;
      final broken = CRDTDocument()
        ..importSnapshot(
          Snapshot(
            id: snapshot.id,
            versionVector: snapshot.versionVector,
            data: {
              ...snapshot.data,
              'crdt_lf/handler-manifest': Uint8List.fromList([0xFF]),
            },
          ),
        );
      expect(handlers(broken)['closed'], [
        {'id': 'text', 'type': null, 'changeCount': 0},
        {'id': 'root', 'type': null, 'changeCount': 0},
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

    test('a container shows the cache it had before the call', () {
      final source = CRDTDocument();
      final child = CRDTTextHandler(source, 'child')..insert(0, 'a');
      CRDTMapRefHandler(source, 'root').setRef('slot', child);
      final doc = CRDTDocument()..importChanges(source.exportChanges());
      CRDTMapRefHandler(doc, 'root');

      // The call reads the children, and so builds the cache, after.
      expect(openHandler(doc, 'root')['cache'], 'none');
      expect(openHandler(doc, 'root')['cache'], 'warm');
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
      final revision = '${result['revision']}';
      expect(
        DevToolsBridge.call(
          'handlerValue',
          {'doc': id, 'handler': 'text', 'revision': revision},
        ),
        {
          'id': 'text',
          'type': result['type'],
          'revision': result['revision'],
          'unchanged': true,
        },
      );
      (doc.handlerById('text')! as CRDTTextHandler).insert(0, 'z');
      expect(
        DevToolsBridge.call(
          'handlerValue',
          {'doc': id, 'handler': 'text', 'revision': revision},
        ),
        containsPair('value', 'zabcdef'),
      );

      for (final params in [
        {'doc': id},
        {'doc': id, 'handler': 'missing'},
        {'doc': id, 'handler': 'text', 'revision': 'x'},
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
      text.insert(0, 'y');

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

    test('changes pages on while older remote changes arrive', () {
      final remote = CRDTDocument(peerId: PeerId.generate());
      final remoteText = CRDTTextHandler(remote, 'text');
      for (var i = 0; i < 3; i++) {
        remoteText.insert(i, 'r');
      }
      final doc = CRDTDocument(peerId: PeerId.generate());
      final text = CRDTTextHandler(doc, 'text');
      for (var i = 0; i < 5; i++) {
        text.insert(i, 'x');
      }
      final id = '${trackedId(doc)}';

      final held = decode(
        DevToolsBridge.call('changes', {'doc': id, 'limit': '2'}),
      );
      // Older than the held changes: they sort before them.
      doc.importChanges(remote.exportChanges());
      while (true) {
        final page = DevToolsBridge.call(
          'changes',
          {'doc': id, 'limit': '2', 'since': sinceOf(held)},
        );
        held.addAll(decode(page));
        if (page['done']! as bool) break;
      }
      expect(held..sort(compareChangeOrder), doc.exportChanges().sorted());
    });

    test('a paging in progress serves a caller that starts over', () {
      final doc = CRDTDocument();
      final text = CRDTTextHandler(doc, 'text');
      for (var i = 0; i < 6; i++) {
        text.insert(i, 'x');
      }
      final id = '${trackedId(doc)}';
      final all = doc.exportChanges().sorted();
      List<Change> page(List<Change> held) => decode(
            DevToolsBridge.call('changes', {
              'doc': id,
              'limit': '2',
              if (held.isNotEmpty) 'since': sinceOf(held),
            }),
          );

      // The copy is built for a caller that already holds two changes.
      expect(page(all.sublist(0, 2)), all.sublist(2, 4));
      expect(page(const []), all.sublist(0, 2));
      // The last page drops the copy.
      expect(DevToolsBridge.held(doc).paging, isTrue);
      expect(page(all.sublist(0, 4)), all.sublist(4));
      expect(DevToolsBridge.held(doc).paging, isFalse);
    });

    test('changes pages past a peer that stopped writing', () {
      final quiet = CRDTDocument(peerId: PeerId.generate());
      CRDTTextHandler(quiet, 'text').insert(0, 'q');
      final doc = CRDTDocument(peerId: PeerId.generate())
        ..importChanges(quiet.exportChanges());
      final text = CRDTTextHandler(doc, 'text');
      for (var i = 0; i < 5; i++) {
        text.insert(0, 'x');
      }
      final id = '${trackedId(doc)}';

      final paged = <Change>[];
      while (true) {
        final page = DevToolsBridge.call('changes', {
          'doc': id,
          'limit': '2',
          if (paged.isNotEmpty) 'since': sinceOf(paged),
        });
        final changes = decode(page);
        expect(changes, hasLength(lessThanOrEqualTo(2)));
        paged.addAll(changes);
        if (page['done']! as bool) break;
      }
      expect(paged, doc.exportChanges().sorted());
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

      final id = '${trackedId(a)}';
      final changes = decode(DevToolsBridge.call('changes', {'doc': id}));
      expect(changes, hasLength(6));
      final paged = <Change>[];
      while (true) {
        final page = DevToolsBridge.call('changes', {
          'doc': id,
          'limit': '2',
          if (paged.isNotEmpty) 'since': sinceOf(paged),
        });
        paged.addAll(decode(page));
        if (page['done']! as bool) break;
      }
      expect(paged, changes);
      expect(changes, [...changes]..sort(compareChangeOrder));
      expect(changes.map((c) => c.author).toSet(), {a.peerId, b.peerId});
    });

    test('a prune that removes nothing keeps the epoch', () async {
      final doc = CRDTDocument();
      final text = CRDTFugueTextHandler(doc, 'text')..insert(0, 'a');
      final undo = CRDTUndoManager(doc)..track(text);
      doc.takeSnapshot();
      final pruned = doc.getVersionVector();
      text.insert(1, 'b');
      expect(documents().single['pruneEpoch'], 1);
      expect(undo.canUndo, isTrue);
      await pumpEventQueue();
      events.clear();

      doc.garbageCollect(pruned);
      expect(documents().single['pruneEpoch'], 1);
      // It still drops the undo history, which the tool shows.
      expect(undo.canUndo, isFalse);
      await pumpEventQueue();
      final event = posted('crdt_lf:devtools:document').single;
      expect(event['pruned'], isFalse);
      expect(event['handlers'], isTrue);
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

    test(
      'a prune releases the changes of a paging in progress',
      () async {
        final doc = CRDTDocument();
        // A function, so no local of the test holds the change.
        WeakReference<Change> pageAndPrune() {
          final text = CRDTTextHandler(doc, 'text')
            ..insert(0, 'a')
            ..insert(0, 'b');
          final first = DevToolsBridge.call(
            'changes',
            {'doc': '${trackedId(doc)}', 'limit': '1'},
          );
          expect(first['done'], isFalse);
          final pruned = WeakReference(doc.exportChanges().first);
          doc.takeSnapshot();
          expect(text.value, 'ba');
          return pruned;
        }

        final pruned = pageAndPrune();
        final stop = DateTime.now().add(const Duration(seconds: 20));
        final garbage = <List<Object>>[];
        while (pruned.target != null) {
          if (DateTime.now().isAfter(stop)) fail('The change stays alive');
          garbage.add(List<Object>.generate(30000, (_) => Object()));
          if (garbage.length > 50) garbage.removeAt(0);
          await Future<void>.delayed(Duration.zero);
        }
        doc.dispose();
      },
      testOn: 'vm',
    );

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

    Map<String, Object?> historyOpen(CRDTDocument doc) =>
        DevToolsBridge.call('historyOpen', {'doc': '${trackedId(doc)}'});

    Map<String, Object?> historyState(
      CRDTDocument doc,
      Object? session,
      int cursor,
    ) =>
        DevToolsBridge.call('historyState', {
          'doc': '${trackedId(doc)}',
          'session': '$session',
          'cursor': '$cursor',
          'handler': 'text',
        });

    test('history shows a handler at the start, middle and end', () {
      final doc = CRDTDocument();
      final text = CRDTTextHandler(doc, 'text')
        ..insert(0, 'a')
        ..insert(1, 'b')
        ..insert(2, 'c');

      final open = historyOpen(doc);
      expect(open['length'], 3);
      expect(open['handlers'], [
        {'id': 'text', 'type': text.handlerType},
      ]);
      expect(open['versionVector'], documents().single['versionVector']);

      final session = open['session'];
      expect(historyState(doc, session, 0), {
        'cursor': 0,
        'frontiers': <String>[],
        'value': '',
      });
      expect(historyState(doc, session, 2)['value'], 'ab');
      final end = historyState(doc, session, 3);
      expect(end['value'], 'abc');
      expect(end['frontiers'], documents().single['frontiers']);
      expect(
        () => historyState(doc, session, 4),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('history opens on a manifest it cannot read', () {
      final source = CRDTDocument();
      final child = CRDTTextHandler(source, 'text')..insert(0, 'a');
      CRDTMapRefHandler(source, 'root').setRef('slot', child);
      final snapshot = source.takeSnapshot();
      final doc = CRDTDocument()
        ..importSnapshot(
          Snapshot(
            id: snapshot.id,
            versionVector: snapshot.versionVector,
            data: {
              ...snapshot.data,
              'crdt_lf/handler-manifest': Uint8List.fromList([0xFF]),
            },
          ),
        );
      final text = CRDTTextHandler(doc, 'text');

      final open = historyOpen(doc);
      expect(open['handlers'], [
        {'id': 'text', 'type': text.handlerType},
      ]);
      expect(historyState(doc, open['session'], 0)['value'], 'a');
    });

    test('an undo manager posts what it moves', () async {
      final doc = CRDTDocument();
      final text = CRDTFugueTextHandler(doc, 'text')..insert(0, 'a');
      Future<void> moves(void Function() act) async {
        await pumpEventQueue();
        events.clear();
        act();
        await pumpEventQueue();
        final event = posted('crdt_lf:devtools:document').single;
        expect(event['handlers'], isTrue);
      }

      late final CRDTUndoManager undo;
      await moves(() => undo = CRDTUndoManager(doc));
      await moves(() => undo.track(text));
      text.insert(0, 'b');
      await moves(undo.clear);
      await moves(() => undo.untrack(text));
      await moves(undo.dispose);
    });

    test('every session before the newest one is replaced', () {
      final doc = CRDTDocument();
      CRDTTextHandler(doc, 'text').insert(0, 'a');
      Matcher refuses(String message) => throwsA(
            isA<ArgumentError>().having((e) => e.message, 'message', message),
          );

      final first = historyOpen(doc)['session'];
      historyOpen(doc);
      final third = historyOpen(doc)['session'];
      expect(() => historyState(doc, first, 0), refuses('Replaced'));

      // The other client closes, then opens again.
      DevToolsBridge.call('historyClose', {
        'doc': '${trackedId(doc)}',
        'session': '$third',
      });
      expect(() => historyState(doc, third, 0), refuses('Not open'));
      historyOpen(doc);
      expect(() => historyState(doc, third, 0), refuses('Replaced'));
      expect(() => historyState(doc, first, 0), refuses('Replaced'));
    });

    test('a second historyOpen or a historyClose ends the session', () {
      final doc = CRDTDocument();
      CRDTTextHandler(doc, 'text').insert(0, 'a');

      final first = historyOpen(doc)['session'];
      final second = historyOpen(doc)['session'];
      expect(second, isNot(first));
      expect(
        () => historyState(doc, first, 0),
        throwsA(
          isA<ArgumentError>().having((e) => e.message, 'message', 'Replaced'),
        ),
      );

      final params = {'doc': '${trackedId(doc)}', 'session': '$second'};
      expect(DevToolsBridge.call('historyClose', params), isEmpty);
      expect(
        () => historyState(doc, second, 0),
        throwsA(
          isA<ArgumentError>().having((e) => e.message, 'message', 'Not open'),
        ),
      );
    });

    test('a session keeps its state while the document moves on', () {
      final doc = CRDTDocument();
      final text = CRDTTextHandler(doc, 'text')..insert(0, 'ab');

      final session = historyOpen(doc)['session'];
      text.insert(2, 'c');

      expect(historyState(doc, session, 1)['value'], 'ab');
    });

    test('snapshot is null before the first snapshot', () {
      final doc = CRDTDocument();
      CRDTTextHandler(doc, 'text').insert(0, 'a');

      expect(DevToolsBridge.call('snapshot', {'doc': '${trackedId(doc)}'}), {
        'snapshot': null,
        'deleted': <String>[],
        'liveRequirements': null,
      });
    });

    test('snapshot describes the last snapshot', () {
      final doc = CRDTDocument();
      final text = CRDTTextHandler(doc, 'text')..insert(0, 'a');
      final taken = doc.takeSnapshot();
      doc.describeDataRequirements();

      final result =
          DevToolsBridge.call('snapshot', {'doc': '${trackedId(doc)}'});
      final snapshot = result['snapshot']! as Map<String, Object?>;
      expect(snapshot['id'], taken.id);
      expect(snapshot['bytes'], taken.toBytes().length);
      expect(snapshot['versionVector'], documents().single['versionVector']);
      const capabilities = 'crdt_lf/capabilities';
      expect(snapshot['entries'], [
        {
          'key': 'text',
          'bytes': taken.data['text']!.length,
          'reserved': false,
          'type': null,
        },
        {
          'key': capabilities,
          'bytes': taken.data[capabilities]!.length,
          'reserved': true,
          'type': null,
        },
      ]);
      expect(snapshot['unfolded'], isEmpty);
      final formats = {text.handlerType: isA<String>()};
      expect(snapshot['requirements'], formats);
      expect(result['liveRequirements'], formats);
    });

    test('snapshot lists a deleted handler', () {
      final doc = CRDTDocument();
      final text = CRDTTextHandler(doc, 'text')..insert(0, 'a');
      doc
        ..deleteHandler(text)
        ..takeSnapshot();

      final result =
          DevToolsBridge.call('snapshot', {'doc': '${trackedId(doc)}'});
      expect(result['deleted'], ['text']);
      final entries =
          (result['snapshot']! as Map<String, Object?>)['entries']! as List;
      expect(
        entries.where((e) => (e as Map)['reserved'] == true),
        isNotEmpty,
      );
    });

    test('snapshot counts unfolded changes and hides a broken record', () {
      final source = CRDTDocument();
      CRDTListHandler<int>(source, 'list', handlerType: 'int-list')
          .insert(0, 1);
      final doc = CRDTDocument()..importChanges(source.exportChanges());
      final taken = doc.takeSnapshot();
      final broken = CRDTDocument()
        ..importSnapshot(
          Snapshot(
            id: taken.id,
            versionVector: taken.versionVector,
            data: {
              ...taken.data,
              'crdt_lf/capabilities': Uint8List.fromList([0xFF]),
            },
          ),
        );

      final snapshot = DevToolsBridge.call(
        'snapshot',
        {'doc': '${trackedId(broken)}'},
      )['snapshot']! as Map<String, Object?>;
      expect(snapshot['unfolded'], {'list': 1});
      expect(snapshot['requirements'], isNull);
    });

    test('the event log reports writes, imports, snapshots and prunes',
        () async {
      final doc = CRDTDocument();
      final text = CRDTTextHandler(doc, 'text');
      final id = trackedId(doc);
      expect(
        DevToolsBridge.call('eventsStart', {'doc': '$id'}),
        {'recording': true, 'renewed': false},
      );
      expect(
        DevToolsBridge.call('eventsStart', {'doc': '$id'})['renewed'],
        isTrue,
      );
      expect(documents().single['recording'], isTrue);

      doc.runInTransaction(
        () => text
          ..insert(0, 'a')
          ..insert(1, 'b')
          ..insert(2, 'c'),
        origin: 'editor',
      );
      final source = CRDTDocument();
      CRDTTextHandler(source, 'text').insert(0, 'z');
      doc.importChanges(source.exportChanges());
      await pumpEventQueue();
      final written = doc.exportChanges();
      final snapshot = doc.takeSnapshot();
      await pumpEventQueue();

      final logged = posted('crdt_lf:devtools:event');
      expect(logged.map((e) => e['type']), [
        'changes',
        'changes',
        'snapshot',
        'pruned',
      ]);
      expect(logged.map((e) => e['n']), [0, 1, 2, 3]);
      expect(logged[0], {
        'doc': id,
        'n': 0,
        'type': 'changes',
        'source': 'created',
        'reason': null,
        'count': logged[0]['count'],
        'ids': logged[0]['ids'],
        'removed': 0,
        'rewritten': 0,
        'snapshotId': null,
        'origin': 'editor'.runtimeType.toString(),
      });
      expect(logged[1], containsPair('source', 'ingested'));
      expect(logged[1]['ids'], [source.exportChanges().single.id.toString()]);
      expect(logged[2], containsPair('reason', 'taken'));
      expect(logged[2], containsPair('snapshotId', snapshot.id));
      expect(logged[3], containsPair('removed', written.length));
      expect(logged[3]['count'], written.length);
    });

    test('eventsStop stops the event log', () async {
      final doc = CRDTDocument();
      final text = CRDTTextHandler(doc, 'text');
      final id = trackedId(doc);
      DevToolsBridge.call('eventsStart', {'doc': '$id'});
      DevToolsBridge.call('eventsStart', {'doc': '$id'});
      text.insert(0, 'a');
      await pumpEventQueue();
      expect(posted('crdt_lf:devtools:event'), hasLength(1));

      expect(
        DevToolsBridge.call('eventsStop', {'doc': '$id'}),
        {'recording': false},
      );
      text.insert(0, 'b');
      await pumpEventQueue();
      expect(posted('crdt_lf:devtools:event'), hasLength(1));
      expect(documents().single['recording'], isFalse);
    });

    test('watch posts the reset and the deltas of a handler', () async {
      final doc = CRDTDocument();
      final text = CRDTTextHandler(doc, 'text')..insert(0, 'a');
      expect(text.value, 'a');
      final id = trackedId(doc);
      final params = {'doc': '$id', 'handler': 'text'};
      expect(
        DevToolsBridge.call('watchStart', params),
        {'watching': true, 'renewed': false},
      );
      expect(DevToolsBridge.call('watchStart', params)['renewed'], isTrue);
      await pumpEventQueue();
      // The cut at 2000 code units falls inside an emoji: it keeps the
      // whole pair out.
      text.insert(1, 'b${'😀' * 1000}');
      await pumpEventQueue();

      final deltas = posted('crdt_lf:devtools:delta');
      expect(deltas, hasLength(2));
      expect(deltas[0], {
        'doc': id,
        'handler': 'text',
        'seq': deltas[0]['seq'],
        'type': 'reset',
        'cause': 'initial',
        'changeId': null,
        'author': null,
        'local': null,
        'origin': null,
        'empty': null,
        'delta': null,
      });
      expect(deltas[1], containsPair('type', 'delta'));
      expect(deltas[1], containsPair('cause', null));
      expect(
        deltas[1],
        containsPair('changeId', doc.version.single.toString()),
      );
      expect(deltas[1], containsPair('author', doc.peerId.toString()));
      expect(deltas[1], containsPair('local', true));
      expect(deltas[1], containsPair('empty', false));
      expect(deltas[1]['delta'], hasLength(1999));
      expect(openHandler(doc, 'text')['watched'], isTrue);

      events.clear();
      expect(DevToolsBridge.call('watchStop', params), {'watching': false});
      text.insert(0, 'c');
      await pumpEventQueue();
      expect(posted('crdt_lf:devtools:delta'), isEmpty);
      expect(openHandler(doc, 'text')['watched'], isFalse);
    });

    test('a watch start or stop posts a handlers move', () async {
      final doc = CRDTDocument();
      CRDTTextHandler(doc, 'text');
      final id = trackedId(doc);
      final params = {'doc': '$id', 'handler': 'text'};
      await pumpEventQueue();

      for (final method in ['watchStart', 'watchStop']) {
        events.clear();
        DevToolsBridge.call(method, params);
        await pumpEventQueue();
        expect(
          posted('crdt_lf:devtools:document'),
          [
            {
              'id': id,
              'changes': false,
              'handlers': true,
              'snapshot': false,
              'pruned': false,
            },
          ],
        );
      }
    });

    test('watch checks the handler', () {
      final doc = CRDTDocument();
      PNCounterHandler(doc, 'counter');
      final id = trackedId(doc);
      for (final params in [
        {'doc': '$id'},
        {'doc': '$id', 'handler': 'missing'},
        {'doc': '$id', 'handler': 'counter'},
      ]) {
        expect(
          () => DevToolsBridge.call('watchStart', params),
          throwsArgumentError,
        );
      }
      expect(
        () => DevToolsBridge.call('watchStop', {'doc': '$id'}),
        throwsArgumentError,
      );
    });

    test('the event log and a watch stop when nobody listens', () async {
      final doc = CRDTDocument();
      final text = CRDTTextHandler(doc, 'text')..insert(0, 'a');
      expect(text.value, 'a');
      final id = trackedId(doc);
      DevToolsBridge.call('eventsStart', {'doc': '$id'});
      DevToolsBridge.call('watchStart', {'doc': '$id', 'handler': 'text'});
      await pumpEventQueue();

      DevToolsBridge.onEvent = null;
      text.insert(1, 'b');
      await pumpEventQueue();
      final listened = developer.extensionStreamHasListener;
      expect(documents().single['recording'], listened);
      expect(openHandler(doc, 'text')['watched'], listened);
    });

    test('the event log and a watch stop when their lease runs out', () async {
      final doc = CRDTDocument();
      final text = CRDTTextHandler(doc, 'text')..insert(0, 'a');
      expect(text.value, 'a');
      final id = trackedId(doc);
      DevToolsBridge.lease = Duration.zero;
      DevToolsBridge.call('eventsStart', {'doc': '$id'});
      DevToolsBridge.call('watchStart', {'doc': '$id', 'handler': 'text'});
      await pumpEventQueue();

      events.clear();
      text.insert(1, 'b');
      await pumpEventQueue();
      expect(posted('crdt_lf:devtools:event'), isEmpty);
      expect(posted('crdt_lf:devtools:delta'), isEmpty);
      expect(documents().single['recording'], isFalse);
      expect(openHandler(doc, 'text')['watched'], isFalse);
    });

    test('a second start renews the lease', () async {
      final doc = CRDTDocument();
      final text = CRDTTextHandler(doc, 'text')..insert(0, 'a');
      expect(text.value, 'a');
      final params = {'doc': '${trackedId(doc)}', 'handler': 'text'};
      DevToolsBridge.lease = const Duration(seconds: 2);
      // Two waits of 1.2 s: the lease holds only if the second start
      // renewed it.
      for (var i = 0; i < 2; i++) {
        DevToolsBridge.call('eventsStart', params);
        DevToolsBridge.call('watchStart', params);
        await Future<void>.delayed(const Duration(milliseconds: 1200));
      }

      events.clear();
      text.insert(1, 'b');
      await pumpEventQueue();
      expect(posted('crdt_lf:devtools:event'), hasLength(1));
      expect(posted('crdt_lf:devtools:delta'), hasLength(1));
    });

    Future<void> runOut() => Future<void>.delayed(DevToolsBridge.lease * 1.5);

    test('a change or a call ends an idle session and an idle paging',
        () async {
      for (final end in <void Function(CRDTTextHandler)>[
        (text) => text.insert(0, 'c'),
        (_) => documents(),
      ]) {
        final doc = CRDTDocument();
        final text = CRDTTextHandler(doc, 'text')
          ..insert(0, 'a')
          ..insert(0, 'b');
        // On its own document: each one must end by itself.
        final paged = CRDTDocument()..importChanges(doc.exportChanges());
        final params = {'doc': '${trackedId(doc)}'};
        final pagedParams = {'doc': '${trackedId(paged)}', 'limit': '1'};
        DevToolsBridge.lease = const Duration(milliseconds: 300);
        DevToolsBridge.call('historyOpen', params);
        DevToolsBridge.call('changes', pagedParams);
        // No receiver: a DevTools tab closed without its close call.
        DevToolsBridge.onEvent = null;
        await runOut();
        expect(DevToolsBridge.held(doc).history, isTrue);
        expect(DevToolsBridge.held(paged).paging, isTrue);

        end(text);
        expect(DevToolsBridge.held(doc).history, isFalse);
        expect(DevToolsBridge.held(paged).paging, isFalse);
      }
    });

    test('a session opens on a document older than the lease', () async {
      final doc = CRDTDocument();
      CRDTTextHandler(doc, 'text').insert(0, 'a');
      final params = {'doc': '${trackedId(doc)}'};
      DevToolsBridge.lease = const Duration(milliseconds: 300);
      await runOut();

      DevToolsBridge.call('historyOpen', params);
      expect(DevToolsBridge.held(doc).history, isTrue);
    });

    test('a page renews the lease of its paging', () async {
      final doc = CRDTDocument();
      final text = CRDTTextHandler(doc, 'text');
      for (var i = 0; i < 5; i++) {
        text.insert(i, 'x');
      }
      final id = '${trackedId(doc)}';
      DevToolsBridge.lease = const Duration(seconds: 2);
      final held = <Change>[];
      // Two waits of 1.2 s: the paging holds only if the second page
      // renewed it.
      for (var i = 0; i < 2; i++) {
        held.addAll(
          decode(
            DevToolsBridge.call('changes', {
              'doc': id,
              'limit': '1',
              if (held.isNotEmpty) 'since': sinceOf(held),
            }),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 1200));
      }
      documents();
      expect(DevToolsBridge.held(doc).paging, isTrue);
    });

    test('a deleted handler leaves no watch', () async {
      final doc = CRDTDocument();
      final text = CRDTTextHandler(doc, 'text')..insert(0, 'a');
      DevToolsBridge.call(
        'watchStart',
        {'doc': '${trackedId(doc)}', 'handler': 'text'},
      );
      expect(DevToolsBridge.held(doc).watched, {'text'});

      doc.deleteHandler(text);
      await pumpEventQueue();
      expect(DevToolsBridge.held(doc).watched, isEmpty);
    });

    test('a historyState past the lease still renews its session', () async {
      final doc = CRDTDocument();
      CRDTTextHandler(doc, 'text').insert(0, 'a');
      final params = {'doc': '${trackedId(doc)}'};
      DevToolsBridge.lease = const Duration(milliseconds: 100);
      final session = DevToolsBridge.call('historyOpen', params)['session'];
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // No change and no call in between: this call is the first to come.
      final state = DevToolsBridge.call('historyState', {
        ...params,
        'session': '$session',
        'cursor': '1',
        'handler': 'text',
      });
      expect(state['value'], 'a');
    });

    test('a historyState renews the lease of its session', () async {
      final doc = CRDTDocument();
      final text = CRDTTextHandler(doc, 'text')..insert(0, 'a');
      DevToolsBridge.lease = const Duration(seconds: 2);
      final session = historyOpen(doc)['session'];
      // Two waits of 1.2 s, each ended by a change, which ends a session
      // past its lease: the session holds only if the first call renewed
      // it.
      for (var i = 0; i < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        text.insert(text.value.length, 'b');
        expect(historyState(doc, session, 1)['value'], 'a');
      }
    });
  });
}
