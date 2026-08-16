import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:crdt_lf/crdt_lf.dart';

import '../common/custom_emitter.dart';

const _kChars = 30000;

/// One local keystroke followed by a read, on a document of [_kChars] runes.
///
/// This is what a text field does on every key: mutate, then ask the handler
/// something. Which question it asks is the point — `length` must not have to
/// resolve the whole sequence to answer.
abstract class _KeystrokeBenchmark extends BenchmarkBase {
  _KeystrokeBenchmark(String read)
      : super(
          'Fugue text keystroke + $read on $_kChars chars',
          emitter: const CustomEmitter(),
        );

  late CRDTFugueTextHandler _text;

  @override
  void setup() {
    final doc = CRDTDocument(peerId: PeerId.generate());
    _text = CRDTFugueTextHandler(doc, 'text');
    doc.runInTransaction(() => _text.insert(0, 'a' * _kChars));
    _text.value;
  }

  /// Reads something off the handler after the keystroke.
  void read(CRDTFugueTextHandler text);

  @override
  void run() {
    _text.insert(1, 'x');
    read(_text);
  }
}

class FugueTextKeystrokeLengthBenchmark extends _KeystrokeBenchmark {
  FugueTextKeystrokeLengthBenchmark() : super('length');

  @override
  void read(CRDTFugueTextHandler text) => text.length;
}

class FugueTextKeystrokeValueBenchmark extends _KeystrokeBenchmark {
  FugueTextKeystrokeValueBenchmark() : super('value');

  @override
  void read(CRDTFugueTextHandler text) => text.value;
}

void main() {
  FugueTextKeystrokeLengthBenchmark().report();
  FugueTextKeystrokeValueBenchmark().report();
}
