import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf/src/algorithm/fugue/tree.dart';
import 'package:crdt_lf/src/handler/fugue/fugue_snapshot.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'package:test/test.dart';

/// One ASCII byte per value, so the framing is what the assertions see.
Uint8List _encodeRun(List<String> values) =>
    Uint8List.fromList(values.join().codeUnits);

List<String> _decodeRun(Uint8List blob, int length) =>
    String.fromCharCodes(blob).split('');

OperationId _stamp(PeerId peer, int l) =>
    OperationId(peer, HybridLogicalClock(l: l, c: 0));

/// Appends [values] to [tree], each one after the last.
void _append(FugueTree<String> tree, PeerId peer, int from, String values) {
  var counter = from;
  for (final value in values.split('')) {
    tree.insert(
      newID: FugueElementID(peer, counter),
      value: value,
      leftOrigin: counter == from
          ? tree.nodes().isEmpty
              ? FugueElementID.nullID()
              : tree.nodes().last.id
          : FugueElementID(peer, counter - 1),
      rightOrigin: FugueElementID.nullID(),
    );
    counter += 1;
  }
}

void main() {
  final peerA = PeerId.parse('00000000-0000-4000-8000-00000000000a');
  final peerB = PeerId.parse('00000000-0000-4000-8000-00000000000b');

  Uint8List write(FugueTree<String> tree, Map<PeerId, int> floor) =>
      FugueSnapshot.write<String>(
        tree: tree,
        floor: floor,
        encodeRun: _encodeRun,
      );

  FugueSnapshotData<String> read(Uint8List bytes) =>
      FugueSnapshot.read<String>(bytes, decodeRun: _decodeRun);

  group('FugueSnapshot', () {
    test('round-trips nodes, stamps and floor through a restored tree', () {
      final tree = FugueTree<String>.empty();
      _append(tree, peerA, 0, 'abc');
      _append(tree, peerB, 0, 'de');
      _append(tree, peerA, 3, 'f');
      tree
        ..delete(FugueElementID(peerA, 1), stamp: _stamp(peerA, 1))
        ..update(
          nodeID: FugueElementID(peerB, 1),
          value: 'E',
          stamp: _stamp(peerB, 7),
        );

      final floor = {peerA: 3, peerB: 1};
      final data = read(write(tree, floor));

      final restored = FugueTree<String>.empty()
        ..bulkSeed(
          data.nodes,
          data.stamps,
          livenessStamps: data.livenessStamps,
          live: data.live,
        );

      expect(restored.values(), equals(tree.values()));
      expect(
        restored.nodes().map((n) => n.id).toList(),
        equals(tree.nodes().map((n) => n.id).toList()),
      );
      for (var i = 0; i < tree.nodes().length; i++) {
        expect(restored.findNodeAtPosition(i), equals(tree.nodes()[i].id));
      }
      expect(restored.stamps, equals(tree.stamps));
      expect(data.floor, equals(floor));
    });

    // Without the stamps a snapshot would let an update this document had
    // already rejected win on reload: a lost update nobody sees.
    test('a restored tree still refuses an update older than the one it kept',
        () {
      final tree = FugueTree<String>.empty();
      _append(tree, peerA, 0, 'ab');
      tree.update(
        nodeID: FugueElementID(peerA, 0),
        value: 'A',
        stamp: _stamp(peerA, 20),
      );

      final data = read(write(tree, {peerA: 1}));
      final restored = FugueTree<String>.empty()
        ..bulkSeed(data.nodes, data.stamps);

      expect(
        restored.update(
          nodeID: FugueElementID(peerA, 0),
          value: 'stale',
          stamp: _stamp(peerA, 10),
        ),
        isFalse,
      );
      expect(restored.values(), equals(['A', 'b']));
    });

    // The point of the run framing: one peer typing into a document spends a
    // handful of bytes on ids instead of one id per element.
    test('a single peer writing in order collapses into one run', () {
      final tree = FugueTree<String>.empty();
      _append(tree, peerA, 0, 'a' * 500);

      final bytes = write(tree, {peerA: 499});
      final runCount = UVarint.read(bytes, offset: 1).value;

      expect(runCount, equals(1));
      expect(read(bytes).nodes, hasLength(500));
      // 500 values, one id, one liveness bitmap, one floor entry: nowhere
      // near an id per element.
      expect(bytes.length, lessThan(700));
    });

    test('a gap in the counters opens a new run', () {
      final tree = FugueTree<String>.empty();
      _append(tree, peerA, 0, 'ab');
      _append(tree, peerA, 5, 'c');

      final bytes = write(tree, {peerA: 5});
      expect(UVarint.read(bytes, offset: 1).value, equals(2));
      expect(
        read(bytes).nodes.map((n) => n.value).toList(),
        equals(['a', 'b', 'c']),
      );
    });

    // A deletion used to cut the run in two and drop the element. Keeping the
    // tombstone inside the run is what lets the element come back whole, and
    // it costs one bit instead of a second id.
    test('a deletion in the middle of a run keeps the run whole', () {
      final tree = FugueTree<String>.empty();
      _append(tree, peerA, 0, 'abc');
      tree.delete(FugueElementID(peerA, 1), stamp: _stamp(peerA, 9));

      final bytes = write(tree, {peerA: 2});
      expect(UVarint.read(bytes, offset: 1).value, equals(1));

      final data = read(bytes);
      expect(data.nodes.map((n) => n.value).toList(), equals(['a', 'b', 'c']));
      expect(data.live, equals([true, false, true]));
      // The table is in the format, and empty: see the note on the writer.
      expect(data.livenessStamps, isEmpty);

      final restored = FugueTree<String>.empty()
        ..bulkSeed(
          data.nodes,
          data.stamps,
          livenessStamps: data.livenessStamps,
          live: data.live,
        );
      expect(restored.values(), equals(['a', 'c']));
    });

    // The writer leaves the liveness table empty, so nothing else exercises
    // the reader for it. It is in the format for the build that will fill it,
    // and a path no test walks is a path that rots.
    test('the reader takes a liveness table the writer does not yet write', () {
      final out = BytesBuilder(copy: false)..addByte(FugueSnapshot.version);
      UVarint.write(1, out); // one run
      out
        ..add(FugueElementID(peerA, 0).toBytes())
        ..addByte(2) // length, as a uvarint
        ..addByte(0x01); // liveness bits: element 0 live, element 1 gone
      final blob = _encodeRun(['a', 'b']);
      UVarint.write(blob.length, out);
      out.add(blob);

      UVarint.write(0, out); // no update stamps
      UVarint.write(1, out); // one liveness stamp
      out
        ..add(FugueElementID(peerA, 1).toBytes())
        ..add(_stamp(peerA, 9).toUint8List());
      UVarint.write(0, out); // empty floor

      final data = read(out.toBytes());

      expect(data.nodes.map((n) => n.value).toList(), equals(['a', 'b']));
      expect(data.live, equals([true, false]));
      expect(
        data.livenessStamps,
        equals({FugueElementID(peerA, 1): _stamp(peerA, 9)}),
      );

      final restored = FugueTree<String>.empty()
        ..bulkSeed(
          data.nodes,
          data.stamps,
          livenessStamps: data.livenessStamps,
          live: data.live,
        );
      expect(restored.values(), equals(['a']));
      expect(
        restored.livenessStamps,
        equals({FugueElementID(peerA, 1): _stamp(peerA, 9)}),
      );
    });

    test('an empty tree round-trips', () {
      final data = read(write(FugueTree<String>.empty(), {}));
      expect(data.nodes, isEmpty);
      expect(data.stamps, isEmpty);
      expect(data.live, isEmpty);
      expect(data.livenessStamps, isEmpty);
      expect(data.floor, isEmpty);
    });

    group('refuses', () {
      late Uint8List valid;

      setUp(() {
        final tree = FugueTree<String>.empty();
        _append(tree, peerA, 0, 'abc');
        valid = write(tree, {peerA: 2});
      });

      test('an empty buffer', () {
        expect(() => read(Uint8List(0)), throwsFormatException);
      });

      test('a version this build does not write', () {
        for (final version in [0, 2, 255]) {
          final other = Uint8List.fromList(valid)..[0] = version;
          expect(
            () => read(other),
            throwsA(
              isA<FormatException>().having(
                (e) => e.message,
                'message',
                contains('Unsupported Fugue snapshot version: $version'),
              ),
            ),
          );
        }
      });

      test('a buffer that stops before the floor', () {
        expect(
          () => read(Uint8List.sublistView(valid, 0, valid.length - 1)),
          throwsFormatException,
        );
      });

      test('a run whose blob holds fewer values than it declares', () {
        // The run of three declares three, the decoder finds two.
        expect(
          () => FugueSnapshot.read<String>(
            valid,
            decodeRun: (blob, length) => _decodeRun(blob, length)..removeLast(),
          ),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('declares 3 elements but decodes to 2'),
            ),
          ),
        );
      });
    });
  });
}
