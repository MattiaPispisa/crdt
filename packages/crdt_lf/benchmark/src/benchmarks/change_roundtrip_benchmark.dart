import 'dart:typed_data';

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:crdt_lf/crdt_lf.dart';

import '../common/custom_emitter.dart';

/// Benchmarks Change.toBytes() for 1000 changes.
///
/// Measures the per-change serialisation cost: envelope encoding +
/// schema version byte + varint deps count + payload length varint.
class ChangeToBytesBenchmark extends BenchmarkBase {
  ChangeToBytesBenchmark()
      : super('Change toBytes x1000', emitter: const CustomEmitter());

  late final List<Change> changes;

  @override
  void setup() {
    final doc = CRDTDocument(peerId: PeerId.generate());
    final list = CRDTListHandler<String>(doc, 'list');
    for (var i = 0; i < 1000; i++) {
      list.insert(i, 'item $i');
    }
    changes = doc.exportChanges();
  }

  @override
  void run() {
    for (final change in changes) {
      change.toBytes();
    }
  }
}

/// Benchmarks Change.fromBytes() for 1000 changes.
///
/// Measures the per-change deserialisation cost.  Note that decoded fields
/// (id, author, deps) are lazy-cached on the resulting Change object, so this
/// only measures the structural parsing, not field access.
class ChangeFromBytesBenchmark extends BenchmarkBase {
  ChangeFromBytesBenchmark()
      : super('Change fromBytes x1000', emitter: const CustomEmitter());

  late final List<Uint8List> encoded;

  @override
  void setup() {
    final doc = CRDTDocument(peerId: PeerId.generate());
    final list = CRDTListHandler<String>(doc, 'list');
    for (var i = 0; i < 1000; i++) {
      list.insert(i, 'item $i');
    }
    encoded = doc.exportChanges().map((c) => c.toBytes()).toList();
  }

  @override
  void run() {
    for (final bytes in encoded) {
      Change.fromBytes(bytes);
    }
  }
}

/// Benchmarks the full Change roundtrip: toBytes() + fromBytes().
class ChangeRoundtripBenchmark extends BenchmarkBase {
  ChangeRoundtripBenchmark()
      : super('Change roundtrip x1000', emitter: const CustomEmitter());

  late final List<Change> changes;

  @override
  void setup() {
    final doc = CRDTDocument(peerId: PeerId.generate());
    final list = CRDTListHandler<String>(doc, 'list');
    for (var i = 0; i < 1000; i++) {
      list.insert(i, 'item $i');
    }
    changes = doc.exportChanges();
  }

  @override
  void run() {
    for (final change in changes) {
      Change.fromBytes(change.toBytes());
    }
  }
}

/// Prints the size of one encoded change per stamped operation kind.
///
/// These are the kinds that resolve a conflict, so they are the ones that
/// used to carry a 24-byte stamp in their envelope on top of the id the change
/// already held. A size is not a run time, so it goes out on its own line
/// rather than through the benchmark emitter.
void _reportChangeSizes() {
  final samples = <String, Change Function()>{
    'fugue text update': () {
      final doc = CRDTDocument(peerId: PeerId.generate());
      final text = CRDTFugueTextHandler(doc, 't')..insert(0, 'ab');
      final before = doc.exportChanges().length;
      text.update(0, 'A');
      return doc.exportChanges().sorted()[before];
    },
    'or-set add': () {
      final doc = CRDTDocument(peerId: PeerId.generate());
      CRDTORSetHandler<String>(doc, 's').add('x');
      return doc.exportChanges().single;
    },
    'or-map put': () {
      final doc = CRDTDocument(peerId: PeerId.generate());
      CRDTORMapHandler<String, int>(doc, 'm').put('k', 1);
      return doc.exportChanges().single;
    },
    'movable list move': () {
      final doc = CRDTDocument(peerId: PeerId.generate());
      final list = CRDTFugueMovableListHandler<String>(doc, 'l')
        ..insertAll(0, ['a', 'b']);
      final before = doc.exportChanges().length;
      list.move(1, 0);
      return doc.exportChanges().sorted()[before];
    },
  };

  for (final entry in samples.entries) {
    final change = entry.value();
    final envelope = OperationEnvelopeCodec.decode(change.payloadBytes());
    // ignore: avoid_print benchmark results
    print(
      'Change size, ${entry.key}(Size): '
      '${change.toBytes().length} bytes total '
      '| ${change.payloadBytes().length} bytes payload '
      '| stamped: ${envelope.stamped}',
    );
  }
}

void main() {
  ChangeToBytesBenchmark().report();
  ChangeFromBytesBenchmark().report();
  ChangeRoundtripBenchmark().report();
  _reportChangeSizes();
}
