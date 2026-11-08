// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:benchmark_infrastructure/benchmark_infrastructure.dart';
import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Timed cycles per batch; see `text_field_benchmark.dart`.
const _measuredCycles = 100;

/// Characters between two formatted runs in the documents below.
const _runLength = 100;

/// A rich text handler of [size] characters, bold on every other run of
/// [_runLength] characters.
CRDTFugueRichTextHandler _document(CRDTDocument document, int size) {
  final note = CRDTFugueRichTextHandler(document, 'note')
    ..insert(0, 'a' * size);
  for (var start = 0; start < size; start += 2 * _runLength) {
    note.format(start, _runLength.clamp(0, size - start), 'bold', true);
  }
  return note;
}

/// Typing into a Fugue rich text handler through [CrdtRichTextFieldBuilder].
///
/// Like `TextFieldBenchmark`, the builder returns a [SizedBox], so the numbers
/// are the binding's own work per keystroke plus one `pump`. The rows vary the
/// size of the document: a cost that grows with it is a cost paid for
/// re-deriving something already known. Compare with the `text_field` rows.
///
/// [debugVerifyCrdtRichTextFieldProjection] is off throughout, because it
/// reads the whole value.
abstract class RichTextFieldBenchmark extends AsyncFixedCycleTimedBenchmark {
  /// Creates a benchmark reported under `name`, driven by [tester].
  RichTextFieldBenchmark(super.name, this.tester)
      : super(measuredCycles: _measuredCycles);

  /// Drives the widget tree these benchmarks live in.
  final WidgetTester tester;

  /// The controller the binding writes to.
  late CrdtRichTextEditingController controller;

  /// Mounts the binding over [document]. Nothing renders the text.
  Future<void> mount(CRDTDocument document) async {
    await tester.pumpWidget(
      CrdtProvider.value(
        value: document,
        child: MaterialApp(
          home: CrdtRichTextFieldBuilder(
            id: 'note',
            builder: (context, richController) {
              controller = richController;
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

/// Typing into formatted text.
class RichTypingBenchmark extends RichTextFieldBenchmark {
  /// Creates the benchmark for a document of [size] characters.
  RichTypingBenchmark(
    WidgetTester tester, {
    required this.size,
    required this.inTheMiddle,
  }) : super(
          'Rich text: one keystroke '
          '${inTheMiddle ? 'in the middle' : 'at the end'}, $size chars',
          tester,
        );

  /// How many characters the document holds to begin with.
  final int size;

  /// Whether the keystroke lands inside the formatted runs.
  final bool inTheMiddle;

  @override
  Future<void> setup() async {
    final document = CRDTDocument();
    _document(document, size);
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

/// Formatting a selection of the field.
class RichFormatBenchmark extends RichTextFieldBenchmark {
  /// Creates the benchmark for a document of [size] characters.
  RichFormatBenchmark(WidgetTester tester, {required this.size})
      : super('Rich text: bold a 50-char selection, $size chars', tester);

  /// How many characters the document holds to begin with.
  final int size;

  var _on = true;

  @override
  Future<void> setup() async {
    final document = CRDTDocument();
    _document(document, size);
    await mount(document);
    _on = true;
  }

  @override
  Future<void> run() async {
    controller.selection = const TextSelection(
      baseOffset: 150,
      extentOffset: 200,
    );
    controller.format('italic', _on ? true : null);
    _on = !_on;
    await tester.pump();
  }
}

/// A toolbar reading the state of six formats over a selection of the whole
/// text, as it does on each change of the selection.
class RichSelectionStateBenchmark extends RichTextFieldBenchmark {
  /// Creates the benchmark for a document of [size] characters.
  RichSelectionStateBenchmark(WidgetTester tester, {required this.size})
      : super(
          'Rich text: 6 format states of a select-all, $size chars',
          tester,
        );

  /// How many characters the document holds to begin with.
  final int size;

  static const _keys = [
    'bold',
    'italic',
    'underline',
    'strike',
    'link',
    'size',
  ];

  @override
  Future<void> setup() async {
    final document = CRDTDocument();
    _document(document, size);
    await mount(document);
    controller.selection = TextSelection(baseOffset: 0, extentOffset: size);
  }

  @override
  Future<void> run() async {
    for (final key in _keys) {
      controller.attributeAtSelection(key);
    }
  }
}

/// Taking in someone else's keystroke or format.
class RichRemoteBenchmark extends RichTextFieldBenchmark {
  /// Creates the benchmark for a document of [size] characters.
  RichRemoteBenchmark(
    WidgetTester tester, {
    required this.size,
    required this.formats,
  }) : super(
          'Rich text: adopt one remote ${formats ? 'format' : 'keystroke'}, '
          '$size chars',
          tester,
        );

  /// How many characters the document holds to begin with.
  final int size;

  /// Whether the remote change is a format, not a keystroke.
  final bool formats;

  late CRDTDocument _document0;
  late CRDTDocument _peer;
  late CRDTFugueRichTextHandler _peerNote;
  var _on = true;

  @override
  Future<void> setup() async {
    _document0 = CRDTDocument();
    _document(_document0, size);

    _peer = CRDTDocument();
    _peerNote = CRDTFugueRichTextHandler(_peer, 'note');
    _peer.importChanges(_document0.exportChanges());
    _on = true;

    await mount(_document0);
  }

  @override
  Future<void> run() async {
    if (formats) {
      _peerNote.format(150, 50, 'italic', _on ? true : null);
      _on = !_on;
    } else {
      _peerNote.insert(_peerNote.length, 'y');
    }
    _document0.importChanges(
      _peer.exportChanges(fromVersionVector: _document0.getVersionVector()),
    );
    await tester.pump();
  }
}

/// Undoing and redoing a keystroke through the manager.
class RichUndoBenchmark extends RichTextFieldBenchmark {
  /// Creates the benchmark for a document of [size] characters.
  RichUndoBenchmark(WidgetTester tester, {required this.size})
      : super('Rich text: type, undo and redo one char, $size chars', tester);

  /// How many characters the document holds to begin with.
  final int size;

  late CRDTUndoManager _manager;

  @override
  Future<void> setup() async {
    final document = CRDTDocument();
    final note = _document(document, size);
    _manager = CRDTUndoManager(
      document,
      trackedOrigins: {crdtRichTextFieldOrigin},
      captureTimeout: Duration.zero,
    )..track(note);
    await tester.pumpWidget(
      CrdtProvider.value(
        value: document,
        child: MaterialApp(
          home: CrdtRichTextFieldBuilder(
            id: 'note',
            undoManager: _manager,
            builder: (context, richController) {
              controller = richController;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
  }

  @override
  Future<void> teardown() async => _manager.dispose();

  @override
  Future<void> run() async {
    keystroke(controller.text.length, 'x');
    controller
      ..undo()
      ..redo()
      ..undo();
    await tester.pump();
  }
}

void main() {
  const timeout = Timeout(Duration(minutes: 10));

  setUp(() => debugVerifyCrdtRichTextFieldProjection = false);
  tearDown(() => debugVerifyCrdtRichTextFieldProjection = true);

  testWidgets(
    'typing',
    (tester) async {
      for (final size in [1000, 10000, 50000]) {
        await RichTypingBenchmark(
          tester,
          size: size,
          inTheMiddle: false,
        ).report();
      }
      await RichTypingBenchmark(
        tester,
        size: 10000,
        inTheMiddle: true,
      ).report();
    },
    timeout: timeout,
  );

  testWidgets(
    'formatting',
    (tester) async {
      for (final size in [10000, 50000]) {
        await RichFormatBenchmark(tester, size: size).report();
      }
    },
    timeout: timeout,
  );

  testWidgets(
    'reading the format state',
    (tester) async {
      for (final size in [10000, 50000]) {
        await RichSelectionStateBenchmark(tester, size: size).report();
      }
    },
    timeout: timeout,
  );

  testWidgets(
    'adopting a remote change',
    (tester) async {
      for (final size in [10000, 50000]) {
        await RichRemoteBenchmark(tester, size: size, formats: false).report();
        await RichRemoteBenchmark(tester, size: size, formats: true).report();
      }
    },
    timeout: timeout,
  );

  testWidgets(
    'undo',
    (tester) async {
      await RichUndoBenchmark(tester, size: 10000).report();
    },
    timeout: timeout,
  );
}
