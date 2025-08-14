import 'dart:math';

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:crdt_lf/crdt_lf.dart';

import '../common/custom_emitter.dart';

class FugueStressBenchmark extends BenchmarkBase {
  FugueStressBenchmark()
      : super(
          'Fugue text editing stress test',
          emitter: const CustomEmitter(),
        );

  late final CRDTDocument doc;
  late final CRDTFugueTextHandler text;
  final random = Random();
  final operations = <void Function()>[];

  @override
  void setup() {
    doc = CRDTDocument(peerId: PeerId.generate());
    text = CRDTFugueTextHandler(doc, 'text');
    text.insert(0, 'Start text' * 100); // Initial long text

    // Prepare a list of random operations to run
    for (var i = 0; i < 500; i++) {
      if (random.nextBool() && text.length > 0) {
        // 50% chance to delete
        final index = random.nextInt(text.length);
        final count = min(5, text.length - index);
        operations.add(() => text.delete(index, count));
      } else {
        // 50% chance to insert
        final index = random.nextInt(text.length + 1);
        operations.add(() => text.insert(index, 'ins'));
      }
    }
  }

  @override
  void run() {
    for (final op in operations) {
      op();
    }
  }
}

void main() {
  FugueStressBenchmark().report();
}
