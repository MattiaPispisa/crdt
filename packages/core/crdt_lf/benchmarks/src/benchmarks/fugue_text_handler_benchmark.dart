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
abstract class _TextEditBenchmark extends TimedBenchmarkBase {
  _TextEditBenchmark(super.name) : super(runsPerMeasure: 1);

  /// How long to run before timing anything.
  ///
  /// By time rather than by cycles, because these workloads are three orders
  /// of magnitude apart and a count that warms one up leaves the other cold.
  /// It matters more than it looks: 20 cycles reported `keystroke + length` at
  /// 26 µs, and the same code fully warmed runs at under 4 µs — the number was
  /// mostly unoptimized code.
  static const _warmup = Duration(milliseconds: 400);

  /// Timed cycles per batch, and how many batches the score is taken over.
  ///
  /// The **fastest** batch wins. A batch of the cheaper benchmarks here is a
  /// few milliseconds, so one garbage collection lands entirely inside it and
  /// multiplies the mean — `update` came out at 4 µs and 22 µs on two
  /// consecutive runs of the same build. The minimum is the cost without
  /// interference, which is what these are comparing.
  static const _measuredCycles = 200;
  static const _batches = 5;

  late CRDTFugueTextHandler _text;

  @override
  void setup() {
    final doc = CRDTDocument(peerId: PeerId.generate());
    _text = CRDTFugueTextHandler(doc, 'text');
    doc.runInTransaction(() => _text.insert(0, 'a' * _kChars));
    _text.value;
  }

  @override
  double measure() {
    setup();
    final warmup = Stopwatch()..start();
    while (warmup.elapsed < _warmup) {
      run();
    }

    var best = double.infinity;
    for (var batch = 0; batch < _batches; batch += 1) {
      // A fresh document per batch, so neither the warm-up nor the batch
      // before it drifts the size the name promises.
      setup();
      final stopwatch = Stopwatch()..start();
      for (var cycle = 0; cycle < _measuredCycles; cycle += 1) {
        run();
      }
      stopwatch.stop();

      final perCycle = stopwatch.elapsedMicroseconds / _measuredCycles;
      if (perCycle < best) {
        best = perCycle;
      }
    }

    teardown();
    return best;
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
