import 'package:benchmark_infrastructure/benchmark_infrastructure.dart';
import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Timed cycles per batch.
///
/// Lower than the shared default because every cycle adds a character. On the
/// 1 000-character row the default would grow the document by a fifth before
/// the batch ends.
const _measuredCycles = 100;

/// Typing into a Fugue text handler through [CrdtTextFieldBuilder].
///
/// ## What is measured, and what is not
///
/// The builder returns a [SizedBox], not a [TextField]. Laying out 50 000
/// characters of real text costs far more than the binding does and would bury
/// the very signal these rows exist to compare — and it is Flutter's cost,
/// identical whatever the binding does underneath. So the numbers are the
/// binding's own work per keystroke, plus one `pump`, which
/// [NoBindingBenchmark] measures on its own so it can be subtracted.
///
/// [debugVerifyCrdtTextFieldProjection] is off throughout. It exists to catch
/// a binding that drifts, and it does so by reading the whole value — the very
/// cost these rows are about. Leaving it on would measure the check instead of
/// the code.
///
/// The rows vary the size of the document on purpose. A cost that grows with
/// it is a cost paid for re-deriving something already known.
abstract class TextFieldBenchmark extends AsyncFixedCycleTimedBenchmark {
  /// Creates a benchmark reported under `name`, driven by [tester].
  TextFieldBenchmark(super.name, this.tester)
      : super(measuredCycles: _measuredCycles);

  /// Drives the widget tree these benchmarks live in.
  final WidgetTester tester;

  /// The controller the binding writes to.
  late TextEditingController controller;

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

  late CRDTDocument _document;
  late CRDTDocument _peer;
  late CRDTFugueTextHandler _peerNote;

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
class HandlerOnlyBenchmark extends FixedCycleTimedBenchmark {
  /// Creates the benchmark for a document of [size] characters.
  HandlerOnlyBenchmark({required this.size, required this.readsTheValue})
      : super(
          'Handler only: insert one char${readsTheValue ? ' and read' : ''}, '
          '$size chars',
          measuredCycles: _measuredCycles,
        );

  /// How many characters the document holds to begin with.
  final int size;

  /// Whether the cycle asks for the value, which rebuilds the whole string.
  final bool readsTheValue;

  late CRDTFugueTextHandler _note;

  @override
  void setup() {
    final document = CRDTDocument();
    // Resolve the projection on the way in, so the first measured cycle is not
    // the only one paying for a cold state.
    _note = CRDTFugueTextHandler(document, 'note')
      ..insert(0, 'a' * size)
      ..value;
  }

  @override
  void run() {
    _note.insert(_note.length, 'x');
    if (readsTheValue && _note.value.isEmpty) {
      throw StateError('empty value');
    }
  }
}

/// The floor: the same loop with nothing but Flutter in it.
///
/// Whatever the rows above cost, this much of it is not the binding.
class NoBindingBenchmark extends AsyncFixedCycleTimedBenchmark {
  /// Creates the benchmark for a controller of [size] characters.
  NoBindingBenchmark(this.tester, {required this.size})
      : super(
          'No binding: one keystroke on a bare controller, $size chars',
          measuredCycles: _measuredCycles,
        );

  /// Drives the widget tree.
  final WidgetTester tester;

  /// How many characters the controller holds to begin with.
  final int size;

  TextEditingController? _controller;

  @override
  Future<void> setup() async {
    _controller?.dispose();
    _controller = TextEditingController(text: 'a' * size);
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
  }

  @override
  Future<void> teardown() async {
    _controller?.dispose();
    _controller = null;
  }

  @override
  Future<void> run() async {
    final controller = _controller!;
    final at = controller.text.length;
    controller.value = TextEditingValue(
      text: controller.text.replaceRange(at, at, 'x'),
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
        HandlerOnlyBenchmark(size: size, readsTheValue: false).report();
        HandlerOnlyBenchmark(size: size, readsTheValue: true).report();
      }
      await NoBindingBenchmark(tester, size: 10000).report();
    },
    timeout: timeout,
  );
}
