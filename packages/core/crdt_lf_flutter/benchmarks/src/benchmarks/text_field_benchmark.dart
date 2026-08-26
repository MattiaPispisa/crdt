import 'package:benchmark_infrastructure/benchmark_infrastructure.dart';
import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// What one keystroke costs through [CrdtTextFieldBuilder].
///
/// ## What is measured, and what is not
///
/// The builder returns a [SizedBox], not a [TextField]. Laying out 50 000
/// characters of real text costs far more than the binding does and would bury
/// the very signal these rows exist to compare — and it is Flutter's cost,
/// identical whatever the binding does underneath. So the numbers are the
/// binding's own work per keystroke, plus one `pump`, which the last row
/// measures on its own so it can be subtracted.
///
/// [debugVerifyCrdtTextFieldProjection] is off throughout. It exists to catch a
/// binding that drifts, and it does so by reading the whole value — the very
/// cost these rows are about. Leaving it on would measure the check instead of
/// the code.
///
/// The rows vary the size of the document on purpose. A cost that grows with
/// it is a cost paid for re-deriving something already known.
abstract class FixedCycleBenchmark extends AsyncTimedBenchmarkBase {
  /// Creates a benchmark reported under `name`.
  FixedCycleBenchmark(super.name);

  static const _warmupCycles = 20;
  static const _cyclesPerBatch = 100;
  static const _batches = 5;

  /// Runs a fixed number of cycles instead of "as many as fit in two seconds",
  /// and reports the **best** batch rather than the mean of all of them.
  ///
  /// A fixed count because every cycle **grows** what it measures: one more
  /// character in the document. The default loop would run tens of thousands
  /// of cycles on the smallest row and end up measuring a document fifteen
  /// times the size the setup built.
  ///
  /// The best batch because a garbage collection or a scheduler hiccup can
  /// only ever make a batch slower, so the fastest one is the closest reading
  /// of what the code costs. Averaging lets one unlucky pause move a row by a
  /// third — more than the differences these rows exist to show.
  @override
  Future<double> measure() async {
    await setup();

    for (var cycle = 0; cycle < _warmupCycles; cycle++) {
      await run();
    }

    var best = double.infinity;
    for (var batch = 0; batch < _batches; batch++) {
      final stopwatch = Stopwatch()..start();
      for (var cycle = 0; cycle < _cyclesPerBatch; cycle++) {
        await run();
      }
      stopwatch.stop();

      final perCycle = stopwatch.elapsedMicroseconds / _cyclesPerBatch;
      if (perCycle < best) {
        best = perCycle;
      }
    }

    await teardown();
    return best;
  }
}

/// A benchmark that drives the binding through a mounted widget.
abstract class TextFieldBenchmark extends FixedCycleBenchmark {
  /// Creates a benchmark reported under `name`, driven by `tester`.
  TextFieldBenchmark(super.name, this.tester);

  /// Drives the widget tree these benchmarks live in.
  final WidgetTester tester;

  /// The controller the binding writes to.
  late final TextEditingController controller;

  /// Mounts the binding over [document]. Nothing renders the text.
  Future<void> mount(CRDTDocument document) async {
    await tester.pumpWidget(
      CrdtProvider.value(
        value: document,
        child: MaterialApp(
          home: CrdtTextFieldBuilder(
            id: 'note',
            builder: (context, textController) {
              controller = textController;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
  }

  /// Writes one character at [at], the way a real field drives its controller.
  void keystroke(int at, String character) {
    controller.value = TextEditingValue(
      text: controller.text.replaceRange(at, at, character),
      selection: TextSelection.collapsed(offset: at + character.length),
    );
  }
}

/// Typing into a Fugue text handler.
class FugueTypingBenchmark extends TextFieldBenchmark {
  /// Creates the benchmark for a document of [size] characters.
  FugueTypingBenchmark(
    WidgetTester tester, {
    required this.size,
    required this.inTheMiddle,
  }) : super(
          'Fugue text: one keystroke '
          '${inTheMiddle ? 'in the middle' : 'at the end'}, $size chars',
          tester,
        );

  /// How many characters the document holds to begin with.
  final int size;

  /// Whether the keystroke lands in the middle, which splits a Fugue run
  /// where an append extends one.
  final bool inTheMiddle;

  @override
  Future<void> setup() async {
    final document = CRDTDocument();
    CRDTFugueTextHandler(document, 'note').insert(0, 'a' * size);
    await mount(document);
  }

  @override
  Future<void> run() async {
    keystroke(
      inTheMiddle ? controller.text.length ~/ 2 : controller.text.length,
      'x',
    );
    await tester.pump();
  }
}

/// Typing into the index-based text handler: no tree, but every operation
/// splices the whole string.
class IndexTypingBenchmark extends TextFieldBenchmark {
  /// Creates the benchmark for a document of [size] characters.
  IndexTypingBenchmark(WidgetTester tester, {required this.size})
      : super('Index text: one keystroke at the end, $size chars', tester);

  /// How many characters the document holds to begin with.
  final int size;

  @override
  Future<void> setup() async {
    final document = CRDTDocument();
    CRDTTextHandler(document, 'note').insert(0, 'a' * size);
    await mount(document);
  }

  @override
  Future<void> run() async {
    keystroke(controller.text.length, 'x');
    await tester.pump();
  }
}

/// Taking in someone else's keystroke.
class RemoteKeystrokeBenchmark extends TextFieldBenchmark {
  /// Creates the benchmark for a document of [size] characters.
  RemoteKeystrokeBenchmark(WidgetTester tester, {required this.size})
      : super('Fugue text: adopt one remote keystroke, $size chars', tester);

  /// How many characters the document holds to begin with.
  final int size;

  late final CRDTDocument _document;
  late final CRDTDocument _peer;
  late final CRDTFugueTextHandler _peerNote;

  @override
  Future<void> setup() async {
    _document = CRDTDocument();
    CRDTFugueTextHandler(_document, 'note').insert(0, 'a' * size);

    _peer = CRDTDocument();
    _peerNote = CRDTFugueTextHandler(_peer, 'note');
    _peer.importChanges(_document.exportChanges());

    await mount(_document);
  }

  @override
  Future<void> run() async {
    _peerNote.insert(_peerNote.length, 'y');
    _document.importChanges(
      _peer.exportChanges(fromVersionVector: _document.getVersionVector()),
    );
    await tester.pump();
  }
}

/// The handler on its own, with no widget at all.
///
/// Attribution: it says how much of a keystroke is the handler rebuilding its
/// projected string, which is the pass the deltas let the binding skip.
class HandlerOnlyBenchmark extends FixedCycleBenchmark {
  /// Creates the benchmark for a document of [size] characters.
  HandlerOnlyBenchmark({required this.size, required this.readsTheValue})
      : super(
          'Handler only: insert one char${readsTheValue ? ' and read' : ''}, '
          '$size chars',
        );

  /// How many characters the document holds to begin with.
  final int size;

  /// Whether the cycle asks for the value, which rebuilds the whole string.
  final bool readsTheValue;

  late final CRDTFugueTextHandler _note;

  @override
  Future<void> setup() async {
    final document = CRDTDocument();
    // Resolve the projection on the way in, so the first measured cycle is not
    // the only one paying for a cold state.
    _note = CRDTFugueTextHandler(document, 'note')
      ..insert(0, 'a' * size)
      ..value;
  }

  @override
  Future<void> run() async {
    _note.insert(_note.length, 'x');
    if (readsTheValue && _note.value.isEmpty) {
      throw StateError('empty value');
    }
  }
}

/// The floor: the same loop with nothing but Flutter in it.
///
/// Whatever the rows above cost, this much of it is not the binding.
class NoBindingBenchmark extends FixedCycleBenchmark {
  /// Creates the benchmark for a controller of [size] characters.
  NoBindingBenchmark(this.tester, {required this.size})
      : super('No binding: one keystroke on a bare controller, $size chars');

  /// Drives the widget tree.
  final WidgetTester tester;

  /// How many characters the controller holds to begin with.
  final int size;

  late final TextEditingController _controller;

  @override
  Future<void> setup() async {
    _controller = TextEditingController(text: 'a' * size);
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
  }

  @override
  Future<void> teardown() async => _controller.dispose();

  @override
  Future<void> run() async {
    final at = _controller.text.length;
    _controller.value = TextEditingValue(
      text: _controller.text.replaceRange(at, at, 'x'),
      selection: TextSelection.collapsed(offset: at + 1),
    );
    await tester.pump();
  }
}

void main() {
  const timeout = Timeout(Duration(minutes: 10));

  setUp(() => debugVerifyCrdtTextFieldProjection = false);
  tearDown(() => debugVerifyCrdtTextFieldProjection = true);

  testWidgets(
    'typing',
    (tester) async {
      for (final size in [1000, 10000, 50000]) {
        await FugueTypingBenchmark(tester, size: size, inTheMiddle: false)
            .report();
      }
      await FugueTypingBenchmark(tester, size: 10000, inTheMiddle: true)
          .report();
      await IndexTypingBenchmark(tester, size: 10000).report();
    },
    timeout: timeout,
  );

  testWidgets(
    'adopting a remote keystroke',
    (tester) async {
      for (final size in [10000, 50000]) {
        await RemoteKeystrokeBenchmark(tester, size: size).report();
      }
    },
    timeout: timeout,
  );

  testWidgets(
    'the handler alone, and the floor',
    (tester) async {
      for (final size in [10000, 50000]) {
        await HandlerOnlyBenchmark(size: size, readsTheValue: false).report();
        await HandlerOnlyBenchmark(size: size, readsTheValue: true).report();
      }
      await NoBindingBenchmark(tester, size: 10000).report();
    },
    timeout: timeout,
  );
}
