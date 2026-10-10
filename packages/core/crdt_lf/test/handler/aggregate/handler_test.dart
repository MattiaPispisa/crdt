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
      final asset = _asset(doc)
        ..dispatchAll(const [NoteAdded('first'), NoteAdded('second')]);
      final change = doc.exportChanges().single;

      expect(
        asset.value.notes.map((note) => note.id),
        [EventId(change.id, 1), EventId(change.id, 0)],
      );
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

  group('spec', () {
    test('declares one kind per readable version, and the blob range', () {
      final spec = CRDTAggregateHandler.spec(
        const _Tags(version: 3, min: 2, migrations: [_TagsV2ToV3()]),
      );

      expect(spec.type, 'test.tags');
      expect(
        spec.formats,
        const HandlerFormats(
          operationKinds: {5, 6},
          blobVersions: BlobVersionRange(2, 3),
        ),
      );
    });

    test('refuses a version outside 1..maxVersion', () {
      expect(
        () => CRDTAggregateHandler.spec(const _Tags(version: 0, min: 0)),
        throwsArgumentError,
      );
      expect(
        () => CRDTAggregateHandler.spec(
          const _Tags(version: AggregateDefinition.maxVersion + 1, min: 1),
        ),
        throwsArgumentError,
      );
    });

    test('refuses a readable version past the current one', () {
      expect(
        () => CRDTAggregateHandler.spec(const _Tags(min: 2)),
        throwsArgumentError,
      );
    });

    test('refuses a gap in the migrations', () {
      expect(
        () => CRDTAggregateHandler.spec(
          const _Tags(version: 3, min: 1, migrations: [_TagsV1ToV2()]),
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
        {4, 6},
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
          const _Tags(version: 3, min: 2, migrations: [_TagsV2ToV3()]),
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
class _Tags extends AggregateDefinition<List<String>, String> {
  const _Tags({this.version = 1, int? min, this.migrations = const []})
      : _min = min;

  static const current = _Tags(
    version: 3,
    min: 1,
    migrations: [_TagsV1ToV2(), _TagsV2ToV3()],
  );

  @override
  final int version;

  final int? _min;

  @override
  int get minReadableVersion => _min ?? version;

  @override
  final List<AggregateMigration> migrations;

  @override
  String get handlerType => 'test.tags';

  @override
  List<String> initial() => const [];

  @override
  List<String> reduce(List<String> state, String event, EventContext context) =>
      [...state, event];

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

class _TagsV1ToV2 extends AggregateMigration {
  const _TagsV1ToV2();

  @override
  int get from => 1;

  @override
  Uint8List upEvent(Uint8List event) => Uint8List.fromList([0, ...event]);

  @override
  Uint8List upState(Uint8List state) =>
      const _JsonListCodec().encode(const _V1StateCodec().decode(state));
}

class _TagsV2ToV3 extends AggregateMigration {
  const _TagsV2ToV3();

  @override
  int get from => 2;

  static String _tag(String tag) => '#${tag.toLowerCase()}';

  @override
  Uint8List upEvent(Uint8List event) =>
      const _V2EventCodec().encode(_tag(const _V2EventCodec().decode(event)));

  @override
  Uint8List upState(Uint8List state) => const _JsonListCodec().encode([
        for (final tag in const _JsonListCodec().decode(state)) _tag(tag),
      ]);
}
