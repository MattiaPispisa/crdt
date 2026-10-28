// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:benchmark_infrastructure/benchmark_infrastructure.dart';
import 'package:crdt_lf/crdt_lf.dart';

import '../common/prepared_cycle_benchmark.dart';

/// What the rich text handler costs, next to the Fugue text handler.
///
/// Every row that has a plain counterpart runs it in the same file, under a
/// `Fugue text (baseline)` name, so the two read side by side from one run.
///
/// The rich text rows come in two shapes:
/// - **plain**: the same runes as the baseline and no mark at all, which is
///   the price of the handler itself;
/// - **marked**: lines of [_kLineLength] runes, each written with
///   [_kAttributes], which is the price of the marks on top. On [_kChars]
///   runes that is [_kLines] lines.

const _kChars = 30000;
const _kLineLength = 30;
const _kLines = _kChars ~/ _kLineLength;
const _kAttributes = <String, Object?>{
  'italic': true,
  'color': '#ff0000',
  'size': 14,
};

/// [lines] lines of [_kLineLength] runes, the last one a `\n`.
String _lines(int lines) => '${'a' * (_kLineLength - 1)}\n' * lines;

/// The document shapes a row runs on.
enum _Shape {
  fugueText('Fugue text (baseline)'),
  richText('Rich text'),
  richTextMarked('Rich text (marked lines)');

  const _Shape(this.label);

  final String label;
}

/// The operations a row calls, over either handler.
abstract class _Text {
  factory _Text(_Shape shape, CRDTDocument doc) {
    switch (shape) {
      case _Shape.fugueText:
        return _FugueText(CRDTFugueTextHandler(doc, 'text'));
      case _Shape.richText:
      case _Shape.richTextMarked:
        return _RichText(CRDTFugueRichTextHandler(doc, 'text'));
    }
  }

  Handler<dynamic> get handler;

  Stream<Object?> watch();

  int get deltaSeq;

  int get length;

  Object get value;

  void insert(int index, String text);

  void delete(int index, int count);
}

class _FugueText implements _Text {
  _FugueText(this.handler);

  @override
  final CRDTFugueTextHandler handler;

  @override
  Stream<Object?> watch() => handler.watch();

  @override
  int get deltaSeq => handler.deltaSeq;

  @override
  int get length => handler.length;

  @override
  Object get value => handler.value;

  @override
  void insert(int index, String text) => handler.insert(index, text);

  @override
  void delete(int index, int count) => handler.delete(index, count);
}

class _RichText implements _Text {
  _RichText(this.handler);

  @override
  final CRDTFugueRichTextHandler handler;

  @override
  Stream<Object?> watch() => handler.watch();

  @override
  int get deltaSeq => handler.deltaSeq;

  @override
  int get length => handler.length;

  @override
  Object get value => handler.value;

  @override
  void insert(int index, String text) => handler.insert(index, text);

  @override
  void delete(int index, int count) => handler.delete(index, count);
}

/// Fills [text] with [chars] runes in the layout of [shape].
void _seed(_Shape shape, _Text text, int chars) {
  final lines = _lines(chars ~/ _kLineLength);
  text.handler.doc.runInTransaction(() {
    if (shape == _Shape.richTextMarked) {
      (text.handler as CRDTFugueRichTextHandler)
          .insert(0, lines, attributes: _kAttributes);
    } else {
      text.insert(0, lines);
    }
  });
  text.value;
}

/// A local edit on a document of [_kChars] runes, rebuilt before each batch.
abstract class _LocalEditBenchmark extends FixedCycleTimedBenchmark {
  _LocalEditBenchmark(this.shape, String operation)
      : super('${shape.label} $operation on $_kChars chars');

  final _Shape shape;

  late _Text text;

  @override
  void setup() {
    text = _Text(shape, CRDTDocument(peerId: PeerId.generate()));
    _seed(shape, text, _kChars);
  }
}

class _KeystrokeLengthBenchmark extends _LocalEditBenchmark {
  _KeystrokeLengthBenchmark(_Shape shape) : super(shape, 'keystroke + length');

  @override
  void run() {
    text
      ..insert(1, 'x')
      ..length;
  }
}

class _KeystrokeValueBenchmark extends _LocalEditBenchmark {
  _KeystrokeValueBenchmark(_Shape shape) : super(shape, 'keystroke + value');

  @override
  void run() {
    text
      ..insert(1, 'x')
      ..value;
  }
}

class _DeleteLengthBenchmark extends _LocalEditBenchmark {
  _DeleteLengthBenchmark(_Shape shape) : super(shape, 'delete + length');

  @override
  void run() {
    text
      ..delete(1, 1)
      ..length;
  }
}

class _DeleteValueBenchmark extends _LocalEditBenchmark {
  _DeleteValueBenchmark(_Shape shape) : super(shape, 'delete + value');

  @override
  void run() {
    text
      ..delete(1, 1)
      ..value;
  }
}

/// One listener on a handler, counting its deltas.
///
/// The benchmark loop never yields, so the stream holds the deltas behind its
/// opening reset instead of handing them over: the handler still builds every
/// one. [close] checks that through [_Text.deltaSeq].
class _Watcher {
  _Watcher(this._text) : _startSeq = _text.deltaSeq {
    _subscription = _text.watch().listen((_) => _events++);
  }

  final _Text _text;
  final int _startSeq;
  StreamSubscription<Object?>? _subscription;
  int _events = 0;

  /// Stops listening, and fails when the handler published no delta.
  void close() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    if (_events == 0 && _text.deltaSeq <= _startSeq + 1) {
      throw StateError('the handler published no delta');
    }
  }
}

/// One insert of [lines] lines on an empty document, with or without
/// [_kAttributes], and with or without a watcher.
class _BulkInsertBenchmark extends FixedCycleTimedBenchmark {
  _BulkInsertBenchmark(
    this.shape,
    this.lines, {
    required this.attributes,
    required this.watched,
  }) : super(
          '${shape.label} insert $lines lines'
          '${attributes ? ' x ${_kAttributes.length} attributes' : ''} '
          '(watched: $watched)',
          measuredCycles: 10,
          batches: 3,
          settleCycles: 1,
        );

  final _Shape shape;
  final int lines;
  final bool attributes;
  final bool watched;

  late final String _text = _lines(lines);

  @override
  void run() {
    final text = _Text(shape, CRDTDocument(peerId: PeerId.generate()));
    final watcher = watched ? _Watcher(text) : null;

    if (attributes) {
      (text.handler as CRDTFugueRichTextHandler)
          .insert(0, _text, attributes: _kAttributes);
    } else {
      text.insert(0, _text);
    }
    if (text.length != _text.length) {
      throw StateError('lost a rune');
    }
    watcher?.close();
  }
}

/// Bold on, then bold off, over half of a document of [_kChars] runes.
class _FormatBenchmark extends FixedCycleTimedBenchmark {
  _FormatBenchmark(this.shape, {required this.watched})
      : super(
          '${shape.label} format bold on/off + length on $_kChars chars '
          '(watched: $watched)',
          measuredCycles: 100,
        );

  final _Shape shape;
  final bool watched;

  late CRDTFugueRichTextHandler _text;
  _Watcher? _watcher;

  @override
  void setup() {
    _watcher?.close();
    final text = _Text(shape, CRDTDocument(peerId: PeerId.generate()));
    _seed(shape, text, _kChars);
    _text = text.handler as CRDTFugueRichTextHandler;
    _watcher = watched ? _Watcher(text) : null;
  }

  @override
  void teardown() {
    _watcher?.close();
    _watcher = null;
  }

  @override
  void run() {
    _text
      ..format(_kChars ~/ 4, _kChars ~/ 2, 'bold', true)
      ..format(_kChars ~/ 4, _kChars ~/ 2, 'bold', null)
      ..length;
  }
}

/// Peer B imports all the changes peer A wrote, one insert per line, then
/// reads the value.
class _ImportBenchmark extends FixedCycleTimedBenchmark {
  _ImportBenchmark(this.shape)
      : super(
          '${shape.label} import $_kLines line inserts + value',
          measuredCycles: 10,
          batches: 3,
          setupPerBatch: false,
        );

  final _Shape shape;

  late List<Change> _changes;

  @override
  void setup() {
    final source = CRDTDocument(peerId: PeerId.generate());
    final text = _Text(shape, source);
    final line = _lines(1);
    for (var i = 0; i < _kLines; i++) {
      if (shape == _Shape.richTextMarked) {
        (text.handler as CRDTFugueRichTextHandler)
            .insert(text.length, line, attributes: _kAttributes);
      } else {
        text.insert(text.length, line);
      }
    }
    _changes = source.exportChanges();
  }

  @override
  void run() {
    final target = CRDTDocument(peerId: PeerId.generate())
      ..importChanges(_changes);
    final text = _Text(shape, target);
    if (text.length != _kChars) {
      throw StateError('lost a rune');
    }
    text.value;
  }
}

/// One remote change on a document of [_kChars] runes, then a read of the
/// value: the live editing loop.
abstract class _RemoteBenchmark extends PreparedCycleBenchmark {
  _RemoteBenchmark(this.shape, String operation)
      : super('${shape.label} remote $operation + value on $_kChars chars');

  final _Shape shape;

  late _Text _source;
  late CRDTDocument _target;
  late _Text _targetText;
  late List<Change> _pending;

  /// Applies the [round]-th edit to the source.
  void edit(_Text source, int round);

  @override
  void setup() {
    final source = CRDTDocument(peerId: PeerId.generate());
    _source = _Text(shape, source);
    _seed(shape, _source, _kChars);

    _target = CRDTDocument(peerId: PeerId.generate())
      ..importChanges(source.exportChanges());
    _targetText = _Text(shape, _target)..value;
  }

  @override
  void prepare(int round) {
    edit(_source, round);
    _pending = _source.handler.doc.exportChanges(
      fromVersionVector: _target.getVersionVector(),
    );
  }

  @override
  void cycle(int round) {
    _target.importChanges(_pending);
    _targetText.value;
  }
}

class _RemoteKeystrokeBenchmark extends _RemoteBenchmark {
  _RemoteKeystrokeBenchmark(_Shape shape) : super(shape, 'keystroke');

  @override
  void edit(_Text source, int round) => source.insert(1, 'x');
}

class _RemoteFormatBenchmark extends _RemoteBenchmark {
  _RemoteFormatBenchmark(_Shape shape) : super(shape, 'format bold on/off');

  @override
  void edit(_Text source, int round) =>
      (source.handler as CRDTFugueRichTextHandler).format(
        _kChars ~/ 4,
        _kChars ~/ 2,
        'bold',
        round.isEven ? true : null,
      );
}

class _SnapshotTakeBenchmark extends TimedBenchmarkBase {
  _SnapshotTakeBenchmark(this.shape, this.elements)
      : super('${shape.label} takeSnapshot of $elements elements');

  final _Shape shape;
  final int elements;

  late CRDTDocument _doc;

  @override
  void setup() {
    _doc = CRDTDocument(peerId: PeerId.generate());
    _seed(shape, _Text(shape, _doc), elements);
  }

  @override
  void run() {
    _doc.takeSnapshot(pruneHistory: false);
  }
}

/// The handler is created after the import, so the read is a
/// `computeState()` with nothing but the snapshot seed behind it.
class _SnapshotRestoreBenchmark extends TimedBenchmarkBase {
  _SnapshotRestoreBenchmark(this.shape, this.elements)
      : super('${shape.label} restore of $elements elements from snapshot');

  final _Shape shape;
  final int elements;

  late Snapshot _snapshot;

  @override
  void setup() {
    final doc = CRDTDocument(peerId: PeerId.generate());
    _seed(shape, _Text(shape, doc), elements);
    _snapshot = doc.takeSnapshot();
  }

  @override
  void run() {
    final doc = CRDTDocument(peerId: PeerId.generate())
      ..importSnapshot(_snapshot);
    _Text(shape, doc).value;
  }
}

/// One undo followed by one redo of a step on a document of [_kChars] runes.
abstract class _UndoRedoBenchmark extends FixedCycleTimedBenchmark {
  _UndoRedoBenchmark(this.shape, String step)
      : super(
          '${shape.label} undo+redo $step on $_kChars chars',
          measuredCycles: 20,
          settleCycles: 2,
        );

  final _Shape shape;

  late CRDTUndoManager _undo;

  /// Takes the step the manager records.
  void step(_Text text);

  @override
  void setup() {
    final doc = CRDTDocument(peerId: PeerId.generate());
    final text = _Text(shape, doc);
    _seed(shape, text, _kChars);
    _undo = CRDTUndoManager(doc, captureTimeout: Duration.zero)
      ..track(text.handler);
    step(text);
    if (!_undo.canUndo) {
      throw StateError('nothing to take back');
    }
  }

  @override
  void run() {
    _undo
      ..undo()
      ..redo();
  }
}

class _UndoFormatBenchmark extends _UndoRedoBenchmark {
  _UndoFormatBenchmark(_Shape shape) : super(shape, 'a bold format');

  @override
  void step(_Text text) => (text.handler as CRDTFugueRichTextHandler)
      .format(_kChars ~/ 4, _kChars ~/ 2, 'bold', true);
}

class _UndoDeleteBenchmark extends _UndoRedoBenchmark {
  _UndoDeleteBenchmark(_Shape shape, this.deleted)
      : super(shape, 'a $deleted-char delete');

  final int deleted;

  @override
  void step(_Text text) => text.delete(_kChars ~/ 2, deleted);
}

void main() {
  for (final shape in _Shape.values) {
    _KeystrokeLengthBenchmark(shape).report();
    _KeystrokeValueBenchmark(shape).report();
    _DeleteLengthBenchmark(shape).report();
    _DeleteValueBenchmark(shape).report();
  }

  for (final lines in [100, _kLines]) {
    for (final watched in [false, true]) {
      _BulkInsertBenchmark(
        _Shape.fugueText,
        lines,
        attributes: false,
        watched: watched,
      ).report();
      _BulkInsertBenchmark(
        _Shape.richText,
        lines,
        attributes: false,
        watched: watched,
      ).report();
      _BulkInsertBenchmark(
        _Shape.richText,
        lines,
        attributes: true,
        watched: watched,
      ).report();
    }
  }

  for (final shape in [_Shape.richText, _Shape.richTextMarked]) {
    for (final watched in [false, true]) {
      _FormatBenchmark(shape, watched: watched).report();
    }
  }

  for (final shape in _Shape.values) {
    _ImportBenchmark(shape).report();
  }
  for (final shape in _Shape.values) {
    _RemoteKeystrokeBenchmark(shape).report();
  }
  for (final shape in [_Shape.richText, _Shape.richTextMarked]) {
    _RemoteFormatBenchmark(shape).report();
  }

  for (final elements in [10000, 100000]) {
    for (final shape in [_Shape.fugueText, _Shape.richTextMarked]) {
      _SnapshotTakeBenchmark(shape, elements).report();
      _SnapshotRestoreBenchmark(shape, elements).report();
    }
  }

  for (final shape in [_Shape.richText, _Shape.richTextMarked]) {
    _UndoFormatBenchmark(shape).report();
  }
  for (final deleted in [1, 100, 500]) {
    for (final shape in _Shape.values) {
      _UndoDeleteBenchmark(shape, deleted).report();
    }
  }
}
