import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:test/test.dart';

import '../../helpers/asset_aggregate.dart';
import '../conformance/handler_conformance.dart';

const _peerA = '00000000-0000-4000-8000-00000000000a';
const _peerB = '00000000-0000-4000-8000-00000000000b';

CRDTAggregateHandler<Asset, AssetEvent> _asset(BaseCRDTDocument doc) =>
    doc.handler(CRDTAggregateHandler.spec(const AssetAggregate()), 'asset-1');

void _sync(CRDTDocument from, CRDTDocument to) {
  to.importChanges(
    from.exportChanges(fromVersionVector: to.getVersionVector()),
  );
}

void main() {
  runHandlerConformanceTests(
    spec: CRDTAggregateHandler.spec(const AssetAggregate()),
    read: (asset) => asset.value.content,
    edit: randomAssetEdit,
  );

  group('CRDTAggregateHandler', () {
    test('a fresh aggregate reads its initial state', () {
      final asset = _asset(CRDTDocument());

      expect(asset.value, const Asset());
    });

    test('dispatchAll writes the events in one change', () {
      final doc = CRDTDocument();
      _asset(doc).dispatchAll(const [
        Renamed('P-101'),
        NoteAdded('Installed'),
        MeasureAdded('12 bar'),
      ]);

      expect(doc.exportChanges(), hasLength(1));
      final received =
          _asset(CRDTDocument()..importChanges(doc.exportChanges())).value;
      expect(received.displayName, 'P-101');
      expect(received.noteTexts, ['Installed']);
      expect(received.measures, ['12 bar']);
    });

    test('dispatchAll of no events writes nothing', () {
      final doc = CRDTDocument();
      _asset(doc).dispatchAll(const []);

      expect(doc.exportChanges(), isEmpty);
    });

    test('an event knows the id of the change and its place in it', () {
      final doc = CRDTDocument();
      final asset = _asset(doc);
      final ids =
          asset.dispatchAll(const [NoteAdded('first'), NoteAdded('second')]);
      final change = doc.exportChanges().single;

      expect(ids, [EventId(change.id, 0), EventId(change.id, 1)]);
      expect(asset.value.notes.map((note) => note.id), ids.reversed);
      expect(asset.dispatch(const Renamed('next')).stamp, isNot(change.id));
    });

    test('the initial state knows the id of the aggregate', () {
      final labels = CRDTDocument()
          .handler(CRDTAggregateHandler.spec(const _Labels()), 'labels-1');

      expect(labels.value, {'aggregate': 'labels-1'});
    });

    test('an update names the note, not its position', () {
      final a = CRDTDocument(peerId: PeerId.parse(_peerA));
      final b = CRDTDocument(peerId: PeerId.parse(_peerB));
      final assetA = _asset(a)..dispatch(const NoteAdded('note'));
      final assetB = _asset(b);
      _sync(a, b);
      final note = assetB.value.notes.single.id;

      assetA.dispatch(const NoteAdded('on top'));
      assetB.dispatch(NoteUpdated(note, 'edited'));
      _sync(a, b);
      _sync(b, a);

      expect(assetA.value.noteTexts, ['on top', 'edited']);
      expect(assetB.value, assetA.value);
    });

    test('a concurrent rename is won by the later stamp', () {
      final a = CRDTDocument(peerId: PeerId.parse(_peerA));
      final b = CRDTDocument(peerId: PeerId.parse(_peerB));
      final assetA = _asset(a)..dispatch(const Renamed('from a'));
      final assetB = _asset(b)..dispatch(const Renamed('from b'));
      _sync(a, b);
      _sync(b, a);

      final changes = a.exportChanges().sorted();
      final winner = changes.last.author == a.peerId ? 'from a' : 'from b';
      expect(assetA.value.displayName, winner);
      expect(assetB.value.displayName, winner);
    });

    test('a nested aggregate resolves to its state', () {
      final doc = CRDTDocument();
      final root = doc.handler(CRDTMapRefHandler.spec, 'root');
      final asset = root.child(
        'asset',
        CRDTAggregateHandler.spec(const AssetAggregate()),
      )..dispatch(const Renamed('nested'));

      expect(root.resolved, {'asset': asset.value});
    });

    test('a peer rebuilds a nested aggregate from its spec', () {
      final doc = CRDTDocument()
        ..register(CRDTAggregateHandler.spec(const AssetAggregate()));
      final source = CRDTDocument();
      final root = source.handler(CRDTMapRefHandler.spec, 'root');
      root
          .child('asset', CRDTAggregateHandler.spec(const AssetAggregate()))
          .dispatch(const Renamed('remote'));

      doc.importChanges(source.exportChanges());

      final rebuilt = doc
          .handler(CRDTMapRefHandler.spec, 'root')
          .getRefAs<CRDTAggregateHandler<Asset, AssetEvent>>('asset');
      expect(rebuilt?.value.displayName, 'remote');
    });
  });

  group('refused events', () {
    CRDTAggregateHandler<List<String>, String> tags(BaseCRDTDocument doc) =>
        doc.handler(CRDTAggregateHandler.spec(const _Tags()), 'tags');

    test('a batch the reducer refuses throws and writes nothing', () {
      final doc = CRDTDocument();
      final handler = tags(doc)..dispatch('red');

      expect(
        () => handler.dispatchAll(const ['blue', 'red']),
        throwsStateError,
      );
      expect(doc.exportChanges(), hasLength(1));
      expect(handler.value, ['red']);
    });

    test('a batch a concurrent event refuses is skipped whole everywhere', () {
      final a = CRDTDocument(peerId: PeerId.parse(_peerA));
      final b = CRDTDocument(peerId: PeerId.parse(_peerB));
      final tagsA = tags(a)..dispatch('red');
      final tagsB = tags(b)..dispatchAll(const ['blue', 'red']);
      _sync(a, b);
      _sync(b, a);

      final first = a.exportChanges().sorted().first.author;
      final expected = first == a.peerId ? ['red'] : ['blue', 'red'];
      expect(tagsA.value, expected);
      expect(tagsB.value, expected);
      final restored = CRDTDocument()..importSnapshot(a.takeSnapshot());
      expect(tags(restored).value, expected);
    });
  });

  group('spec', () {
    test('declares one kind per readable version, and the blob range', () {
      final spec = CRDTAggregateHandler.spec(
        const _Tags(version: 3, migrations: [_TagsV2ToV3()]),
      );

      expect(spec.type, 'test.tags');
      expect(
        spec.formats,
        const HandlerFormats(
          operationKinds: {17, 18},
          blobVersions: BlobVersionRange(2, 3),
        ),
      );
    });

    test('refuses a version outside 1..maxVersion', () {
      expect(
        () => CRDTAggregateHandler.spec(const _Tags(version: 0)),
        throwsArgumentError,
      );
      expect(
        () => CRDTAggregateHandler.spec(
          const _Tags(version: AggregateDefinition.maxVersion + 1),
        ),
        throwsArgumentError,
      );
    });

    test('refuses a migration past the current version', () {
      expect(
        () => CRDTAggregateHandler.spec(
          const _Tags(version: 2, migrations: [_TagsV1ToV2(), _TagsV2ToV3()]),
        ),
        throwsArgumentError,
      );
    });

    test('refuses a gap in the migrations', () {
      expect(
        () => CRDTAggregateHandler.spec(
          const _Tags(version: 3, migrations: [_TagsV1ToV2()]),
        ),
        throwsArgumentError,
      );
    });

    test('refuses two migrations from one version', () {
      expect(
        () => CRDTAggregateHandler.spec(
          const _Tags(version: 2, migrations: [_TagsV1ToV2(), _TagsV1ToV2()]),
        ),
        throwsArgumentError,
      );
    });

    test('the highest version still fits the kind byte', () {
      final spec = CRDTAggregateHandler.spec(
        const _Tags(version: AggregateDefinition.maxVersion),
      );

      expect(spec.formats.operationKinds, {OperationType.maxKind});
    });
  });

  group('migrations', () {
    CRDTAggregateHandler<List<String>, String> tags(
      BaseCRDTDocument doc,
      _Tags definition,
    ) =>
        doc.handler(CRDTAggregateHandler.spec(definition), 'tags');

    test('events of an older version are upcast as they are read', () {
      final v1 = CRDTDocument();
      tags(v1, const _Tags()).dispatchAll(const ['Red', 'Green']);

      final v3 = CRDTDocument()..importChanges(v1.exportChanges());

      expect(tags(v3, _Tags.current).value, ['#red', '#green']);
    });

    test('a snapshot of an older version is upcast as it is read', () {
      final v1 = CRDTDocument();
      tags(v1, const _Tags()).dispatch('Red');
      v1.takeSnapshot();

      final v3 = CRDTDocument()..importSnapshot(v1.snapshot!);

      expect(tags(v3, _Tags.current).value, ['#red']);
    });

    test('snapshot and history upcast to the same state', () {
      final v1 = CRDTDocument();
      final handler = tags(v1, const _Tags())..dispatchAll(const ['A', 'B']);
      final before = v1.exportChanges();
      v1.takeSnapshot(pruneHistory: false);
      handler.dispatch('C');

      final fromHistory = CRDTDocument()..importChanges(v1.exportChanges());
      final fromSnapshot = CRDTDocument()
        ..import(
          snapshot: v1.snapshot,
          changes: v1
              .exportChanges()
              .where((change) => !before.contains(change))
              .toList(),
        );

      expect(
        tags(fromSnapshot, _Tags.current).value,
        tags(fromHistory, _Tags.current).value,
      );
      expect(tags(fromHistory, _Tags.current).value, ['#a', '#b', '#c']);
    });

    test('a migration splits or drops an event, and ids never move', () {
      final v1 = CRDTDocument();
      CRDTAggregateHandler<Map<String, Object>, String> labels(
        BaseCRDTDocument doc,
        int version,
      ) =>
          doc.handler(CRDTAggregateHandler.spec(_Labels(version)), 'labels');
      labels(v1, 1).dispatchAll(const ['x*w+y', '', 'z']);
      final stamp = v1.exportChanges().single.id;
      EventId id(int index, [int part = 0]) =>
          EventId(stamp, index, part: part);

      final v2 = CRDTDocument()..importChanges(v1.exportChanges());
      final v3 = CRDTDocument()..importChanges(v1.exportChanges());

      expect(labels(v2, 2).value, {
        'aggregate': 'labels',
        'x*w': id(0),
        'y': id(0, 1),
        'z': id(2),
      });
      expect(labels(v3, 3).value, {
        'aggregate': 'labels',
        'x': id(0),
        'w': id(0, 2),
        'y': id(0, 1),
        'z': id(2),
      });
    });

    test('new events are written in the current version', () {
      final v1 = CRDTDocument();
      tags(v1, const _Tags()).dispatch('Old');
      final v3 = CRDTDocument()..importChanges(v1.exportChanges());
      tags(v3, _Tags.current).dispatch('#new');

      expect(
        v3
            .describeDataRequirements()
            .byHandlerType['test.tags']
            ?.operationKinds,
        {16, 18},
      );
      expect(tags(v3, _Tags.current).value, ['#old', '#new']);
    });

    test('an older build refuses events of a newer version', () {
      final v3 = CRDTDocument();
      tags(v3, _Tags.current).dispatch('#new');

      final v1 = CRDTDocument()..importChanges(v3.exportChanges());

      expect(
        () => tags(v1, const _Tags()).value,
        throwsA(isA<UnknownOperationKindException>()),
      );
    });

    test('an older build refuses a snapshot of a newer version', () {
      final v3 = CRDTDocument();
      tags(v3, _Tags.current).dispatch('#new');
      v3.takeSnapshot();

      final v1 = CRDTDocument()..importSnapshot(v3.snapshot!);

      expect(() => tags(v1, const _Tags()).value, throwsFormatException);
    });

    test('a build refuses events below its readable version', () {
      final v1 = CRDTDocument();
      tags(v1, const _Tags()).dispatch('Old');

      final v3 = CRDTDocument()..importChanges(v1.exportChanges());

      expect(
        () => tags(
          v3,
          const _Tags(version: 3, migrations: [_TagsV2ToV3()]),
        ).value,
        throwsA(isA<UnknownOperationKindException>()),
      );
    });
  });

  group('undo', () {
    test('a definition that cannot invert cannot be tracked', () {
      final doc = CRDTDocument();
      final handler = CRDTAggregateHandler<List<String>, String>(
        doc,
        'tags',
        definition: const _Tags(),
      );

      expect(handler.invertible, isFalse);
      expect(
        () => CRDTUndoManager(doc).track(handler),
        throwsUnsupportedError,
      );
    });

    test('undo takes a whole batch back, redo puts it again', () {
      final doc = CRDTDocument();
      final asset = _asset(doc)..dispatch(const Renamed('start'));
      final undo = CRDTUndoManager(doc, captureTimeout: Duration.zero)
        ..track(asset);

      asset.dispatchAll(const [Renamed('next'), NoteAdded('note')]);
      final after = asset.value;

      undo.undo();
      expect(asset.value, const Asset(displayName: 'start'));

      undo.redo();
      expect(asset.value, after);
    });

    test('an event with no inverse records no step', () {
      final doc = CRDTDocument();
      final asset = _asset(doc);
      final undo = CRDTUndoManager(doc)..track(asset);

      asset.dispatch(const MeasureAdded('5 bar'));

      expect(undo.canUndo, isFalse);
    });
  });

  group('deltas', () {
    test('a local batch is one delta carrying its events', () async {
      final doc = CRDTDocument();
      final asset = _asset(doc)..value;
      final updates = <HandlerUpdate<AggregateDelta<Asset, AssetEvent>>>[];
      final subscription = asset.watch().listen(updates.add);
      await Future<void>.delayed(Duration.zero);

      asset.dispatchAll(const [Renamed('P-101'), MeasureAdded('5 bar')]);
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();

      final delta = updates
          .whereType<HandlerDelta<AggregateDelta<Asset, AssetEvent>>>()
          .single
          .delta;
      expect(delta.previous, const Asset());
      expect(delta.current, asset.value);
      expect(
        delta.events.map((event) => event.event),
        const [Renamed('P-101'), MeasureAdded('5 bar')],
      );
      expect(asset.applyDelta(const Asset(), delta), asset.value);
    });
  });
}

/// A list of tags whose format changed twice.
///
/// - v1: an event is the tag in UTF-8; the state is the tags joined by `\n`.
/// - v2: an event is `[0][tag]` (`0` = add); the state is a JSON list.
/// - v3: tags are lower case and start with `#`.
final class _Tags extends AggregateDefinition<List<String>, String> {
  const _Tags({this.version = 1, this.migrations = const []});

  static const current = _Tags(
    version: 3,
    migrations: [_TagsV1ToV2(), _TagsV2ToV3()],
  );

  @override
  final int version;

  @override
  final List<AggregateMigration> migrations;

  @override
  String get handlerType => 'test.tags';

  @override
  List<String> initial(String id) => const [];

  @override
  List<String> reduce(List<String> state, String event, EventContext context) {
    if (state.contains(event)) {
      throw StateError('The tag $event is already there.');
    }
    return [...state, event];
  }

  @override
  ValueCodec<String> get eventCodec =>
      version == 1 ? const _V1EventCodec() : const _V2EventCodec();

  @override
  ValueCodec<List<String>> get stateCodec =>
      version == 1 ? const _V1StateCodec() : const _JsonListCodec();
}

class _V1EventCodec implements ValueCodec<String> {
  const _V1EventCodec();

  @override
  Uint8List encode(String value) => utf8.encode(value);

  @override
  String decode(Uint8List bytes) => utf8.decode(bytes);
}

class _V2EventCodec implements ValueCodec<String> {
  const _V2EventCodec();

  @override
  Uint8List encode(String value) =>
      Uint8List.fromList([0, ...utf8.encode(value)]);

  @override
  String decode(Uint8List bytes) {
    if (bytes.first != 0) {
      throw const FormatException('Unknown tag event');
    }
    return utf8.decode(bytes.sublist(1));
  }
}

class _V1StateCodec implements ValueCodec<List<String>> {
  const _V1StateCodec();

  @override
  Uint8List encode(List<String> value) => utf8.encode(value.join('\n'));

  @override
  List<String> decode(Uint8List bytes) {
    final text = utf8.decode(bytes);
    return text.isEmpty ? const [] : text.split('\n');
  }
}

class _JsonListCodec implements ValueCodec<List<String>> {
  const _JsonListCodec();

  @override
  Uint8List encode(List<String> value) => utf8.encode(jsonEncode(value));

  @override
  List<String> decode(Uint8List bytes) =>
      (jsonDecode(utf8.decode(bytes)) as List<dynamic>).cast<String>();
}

final class _TagsV1ToV2 extends AggregateMigration {
  const _TagsV1ToV2();

  @override
  int get from => 1;

  @override
  List<Uint8List> upEvent(Uint8List event) => [
        Uint8List.fromList([0, ...event]),
      ];

  @override
  Uint8List upState(Uint8List state) =>
      const _JsonListCodec().encode(const _V1StateCodec().decode(state));
}

final class _TagsV2ToV3 extends AggregateMigration {
  const _TagsV2ToV3();

  @override
  int get from => 2;

  static String _tag(String tag) => '#${tag.toLowerCase()}';

  @override
  List<Uint8List> upEvent(Uint8List event) => [
        const _V2EventCodec().encode(_tag(const _V2EventCodec().decode(event))),
      ];

  @override
  Uint8List upState(Uint8List state) => const _JsonListCodec().encode([
        for (final tag in const _JsonListCodec().decode(state)) _tag(tag),
      ]);
}

/// Keeps, under each label, the id of the event that wrote it.
///
/// - v1: an event is a label in UTF-8.
/// - v2: `+` splits a v1 event in several; an empty one is dropped.
/// - v3: `*` splits a v2 event in several.
final class _Labels extends AggregateDefinition<Map<String, Object>, String> {
  const _Labels([this.version = 1]);

  @override
  final int version;

  @override
  String get handlerType => 'test.labels';

  @override
  Map<String, Object> initial(String id) => {'aggregate': id};

  @override
  Map<String, Object> reduce(
    Map<String, Object> state,
    String event,
    EventContext context,
  ) =>
      {...state, event: context.id};

  @override
  List<AggregateMigration> get migrations => const [
        _SplitLabels(1, '+'),
        _SplitLabels(2, '*'),
      ].sublist(0, version - 1);

  @override
  ValueCodec<String> get eventCodec => const _V1EventCodec();

  @override
  ValueCodec<Map<String, Object>> get stateCodec => throw UnimplementedError();
}

final class _SplitLabels extends AggregateMigration {
  const _SplitLabels(this.from, this.separator);

  @override
  final int from;

  final String separator;

  @override
  List<Uint8List> upEvent(Uint8List event) {
    final label = utf8.decode(event);
    return [
      if (label.isNotEmpty)
        for (final part in label.split(separator)) utf8.encode(part),
    ];
  }

  @override
  Uint8List upState(Uint8List state) => state;
}
