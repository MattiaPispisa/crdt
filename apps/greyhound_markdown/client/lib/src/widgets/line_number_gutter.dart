import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// The horizontal breathing room around the numbers. Kept tight: the field
/// next to the gutter already has padding of its own.
const double _kGutterPadding = 4;

/// The smallest number of digits the gutter reserves, so a short document does
/// not sit in a sliver of a column.
const int _kMinDigits = 2;

/// The widest the gutter grows. Past it the numbers are scaled down to fit
/// rather than taking more room from the text.
const int _kMaxDigits = 4;

/// The width a gutter needs for a document of [lineCount] lines drawn in
/// [style].
///
/// Grows with the digit count instead of with the text, so the editor next to
/// it only shifts when the document crosses 100, 1000, … lines — and stops
/// growing at [_kMaxDigits].
double lineNumberGutterWidth(int lineCount, TextStyle style) {
  final digits = '$lineCount'.length.clamp(_kMinDigits, _kMaxDigits);
  final painter = TextPainter(
    text: TextSpan(text: '0' * digits, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  final width = painter.width + _kGutterPadding * 2;
  painter.dispose();
  return width;
}

/// The offset in [text] where each line starts, the first one included.
///
/// An empty document still has one line, so the list is never empty.
List<int> lineStartOffsets(String text) {
  final starts = <int>[0];
  for (var i = 0; i < text.length; i++) {
    if (text.codeUnitAt(i) == 0x0A) {
      starts.add(i + 1);
    }
  }
  return starts;
}

/// The style to draw the line numbers of [editable] in, keeping the color of
/// [fallback].
///
/// It is the field's **own** text style, not the one the app passed to the
/// field: `TextField` merges that into the theme's `bodyLarge`, which carries
/// `height: 1.5`. A number laid out without it gets a box a third shorter than
/// the line, and ends up drawn above the text it numbers.
TextStyle gutterNumberStyle(RenderEditable editable, TextStyle fallback) {
  final style = editable.text?.style;
  return style == null ? fallback : style.copyWith(color: fallback.color);
}

/// A line number and the y it is painted at, in the gutter's coordinates.
typedef GutterLine = ({int number, double top});

/// The line numbers visible in a gutter [height] tall next to [editable].
///
/// Each number sits at the caret top of its line's first character, so a
/// logical line that wraps over several visual rows still gets exactly one
/// number, next to its first row. The field's vertical scroll and its content
/// padding are already inside [toGutter] — nothing is measured twice here.
///
/// Only the visible lines come back. A line's top grows with its offset, so
/// the first visible one is a binary search away: a document of ten thousand
/// lines costs about fourteen probes, not ten thousand.
List<GutterLine> resolveGutterLines({
  required RenderEditable editable,
  required Matrix4 toGutter,
  required double height,
}) {
  final starts = lineStartOffsets(editable.plainText);
  final lineHeight = editable.preferredLineHeight;

  double topOf(int line) => MatrixUtils.transformRect(
    toGutter,
    editable.getLocalRectForCaret(TextPosition(offset: starts[line])),
  ).top;

  var low = 0;
  var high = starts.length - 1;
  while (low < high) {
    final middle = (low + high) ~/ 2;
    if (topOf(middle) + lineHeight < 0) {
      low = middle + 1;
    } else {
      high = middle;
    }
  }

  final lines = <GutterLine>[];
  for (var line = low; line < starts.length; line++) {
    final top = topOf(line);
    if (top > height) {
      break;
    }
    lines.add((number: line + 1, top: top));
  }
  return lines;
}

/// The numbered column drawn next to the editor.
///
/// It takes its geometry from the text field itself — the [RenderEditable]
/// found under [fieldKey] — rather than laying the text out a second time.
/// That is what keeps a number next to its line when the line soft-wraps over
/// several visual lines: a second measurement with its own [TextPainter] would
/// drift as soon as the two layouts disagreed by a pixel.
///
/// The same trick is what `CrdtTextCursorsOverlay` uses to place remote
/// carets.
class LineNumberGutter extends StatefulWidget {
  /// Creates a line-number gutter.
  const LineNumberGutter({
    required this.controller,
    required this.scrollController,
    required this.fieldKey,
    required this.width,
    required this.style,
    super.key,
  });

  /// The editor's controller; its text says where the lines start.
  final TextEditingController controller;

  /// The field's vertical scroll, so the numbers travel with the text.
  final ScrollController scrollController;

  /// Key of the widget holding the text field to measure.
  final GlobalKey fieldKey;

  /// Width of the column, from [lineNumberGutterWidth].
  final double width;

  /// Style of the numbers.
  final TextStyle style;

  @override
  State<LineNumberGutter> createState() => _LineNumberGutterState();
}

class _LineNumberGutterState extends State<LineNumberGutter> {
  final _repaint = _RepaintNotifier();

  /// Cached [RenderEditable] of the field; re-resolved once it detaches.
  RenderEditable? _editable;

  /// One laid-out [TextPainter] per number. A scrolling document keeps asking
  /// for the same few dozen numbers frame after frame.
  final _numbers = <int, TextPainter>{};

  /// The style the numbers were last laid out with.
  TextStyle? _numberStyle;

  @override
  void dispose() {
    _clearNumbers();
    _repaint.dispose();
    super.dispose();
  }

  void _clearNumbers() {
    for (final painter in _numbers.values) {
      painter.dispose();
    }
    _numbers.clear();
  }

  /// A number laid out with [style].
  ///
  /// [style] is the field's own text style, not this widget's: the theme adds
  /// a line height to it (`bodyLarge` carries `height: 1.5`), and a number
  /// laid out without it gets a shorter box, so it would sit above the line it
  /// numbers.
  TextPainter _numberPainter(int number, TextStyle style) {
    if (_numberStyle != style) {
      _numberStyle = style;
      _clearNumbers();
    }
    return _numbers.putIfAbsent(
      number,
      () => TextPainter(
        text: TextSpan(text: '$number', style: style),
        textDirection: TextDirection.ltr,
      )..layout(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      // Decoration only. A CustomPaint absorbs hits by default, which would
      // eat a drag that started on the gutter.
      child: IgnorePointer(
        child: CustomPaint(painter: _GutterPainter(this)),
      ),
    );
  }

  /// The [RenderEditable] of the text field next to this gutter.
  RenderEditable? _findEditable() {
    if (_editable != null && _editable!.attached) {
      return _editable;
    }
    _editable = null;
    void visit(RenderObject node) {
      if (_editable != null) {
        return;
      }
      if (node is RenderEditable) {
        _editable = node;
        return;
      }
      node.visitChildren(visit);
    }

    widget.fieldKey.currentContext?.findRenderObject()?.visitChildren(visit);
    return _editable;
  }
}

class _RepaintNotifier extends ChangeNotifier {
  void bump() => notifyListeners();
}

/// Paints the visible line numbers.
///
/// Only the lines on screen are drawn: the first one is found by binary
/// search (a line's top only grows with its offset), so a long document costs
/// a handful of measurements per frame instead of one per line.
class _GutterPainter extends CustomPainter {
  _GutterPainter(this._state)
    : super(
        repaint: Listenable.merge([
          _state._repaint,
          _state.widget.controller,
          _state.widget.scrollController,
        ]),
      );

  final _LineNumberGutterState _state;

  @override
  void paint(Canvas canvas, Size size) {
    final editable = _state._findEditable();
    final gutter = _state.context.findRenderObject();
    if (editable == null ||
        !editable.attached ||
        gutter is! RenderBox ||
        !gutter.hasSize) {
      // The field is not laid out yet (first frame): come back next frame.
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _state._repaint.bump(),
      );
      return;
    }

    final lines = resolveGutterLines(
      editable: editable,
      toGutter: editable.getTransformTo(gutter),
      height: size.height,
    );

    final style = gutterNumberStyle(editable, _state.widget.style);
    final available = size.width - _kGutterPadding * 2;
    canvas
      ..save()
      ..clipRect(Offset.zero & size);
    for (final line in lines) {
      final painter = _state._numberPainter(line.number, style);
      // Past the gutter's widest digit count a number is shrunk to fit
      // instead of spilling over the text.
      final scale = painter.width > available
          ? available / painter.width
          : 1.0;
      if (scale == 1) {
        painter.paint(
          canvas,
          Offset(size.width - _kGutterPadding - painter.width, line.top),
        );
        continue;
      }
      canvas
        ..save()
        ..translate(_kGutterPadding, line.top)
        ..scale(scale);
      painter.paint(canvas, Offset.zero);
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GutterPainter oldDelegate) => true;
}
