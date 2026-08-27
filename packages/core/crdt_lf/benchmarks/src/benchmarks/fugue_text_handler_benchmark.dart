import 'package:benchmark_infrastructure/benchmark_infrastructure.dart';
import 'package:crdt_lf/crdt_lf.dart';

const _kChars = 30000;

/// A benchmark over a document of [_kChars] runes whose `run()` leaves state
/// behind — a rune in the tree, a change in the history, or both.
///
/// The harness loop would keep going for two seconds, so the document would
/// drift far past the size in the name, by an amount that depends on how fast
/// the machine is. This times a fixed number of cycles on a document rebuilt
/// for the occasion instead.
abstract class _TextEditBenchmark extends FixedCycleTimedBenchmark {
  _TextEditBenchmark(super.name);

  late CRDTFugueTextHandler _text;

  @override
  void setup() {
    final doc = CRDTDocument(peerId: PeerId.generate());
    _text = CRDTFugueTextHandler(doc, 'text');
    doc.runInTransaction(() => _text.insert(0, 'a' * _kChars));
    _text.value;
  }
}

/// One local keystroke followed by a read.
///
/// This is what a text field does on every key: mutate, then ask the handler
/// something. Which question it asks is the point — `length` must not have to
/// resolve the whole sequence to answer.
abstract class _KeystrokeBenchmark extends _TextEditBenchmark {
  _KeystrokeBenchmark(String read)
      : super('Fugue text keystroke + $read on $_kChars chars');

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

/// The isolated cost of an `update`, in place of the insert+read the
/// keystroke benchmarks above measure.
///
/// `update` resolves the target through the positional index the same way
/// `insert`/`delete` do, so this is what tells the two apart from a single
/// combined number. It adds no rune, but it does add a change to the history
/// on every call, which is why it shares the fixed-cycle loop.
class FugueTextUpdateBenchmark extends _TextEditBenchmark {
  FugueTextUpdateBenchmark() : super('Fugue text update on $_kChars chars');

  @override
  void run() {
    _text.update(_kChars ~/ 2, 'x');
  }
}

void main() {
  FugueTextKeystrokeLengthBenchmark().report();
  FugueTextKeystrokeValueBenchmark().report();
  FugueTextUpdateBenchmark().report();
}
