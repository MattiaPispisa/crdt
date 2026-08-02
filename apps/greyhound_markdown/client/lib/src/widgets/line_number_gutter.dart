import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// The horizontal breathing room around the numbers.
const double _kGutterPadding = 8;

/// The smallest number of digits the gutter reserves, so a short document does
/// not sit in a sliver of a column.
const int _kMinDigits = 2;

/// The width a gutter needs for a document of [lineCount] lines drawn in
/// [style].
///
/// Grows with the digit count instead of with the text, so the editor next to
/// it only shifts when the document crosses 100, 1000, … lines.
double lineNumberGutterWidth(int lineCount, TextStyle style) {
  final digits = '$lineCount'.length.clamp(_kMinDigits, 12);
  final painter = TextPainter(
    text: TextSpan(text: '0' * digits, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  return painter.width + _kGutterPadding * 2;
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

  @override
  void dispose() {
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: CustomPaint(painter: _GutterPainter(this)),
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

    final transform = editable.getTransformTo(gutter);
    final starts = lineStartOffsets(_state.widget.controller.text);

    double topOf(int line) => MatrixUtils.transformRect(
      transform,
      editable.getLocalRectForCaret(TextPosition(offset: starts[line])),
    ).top;

    // First line whose bottom is still below the top edge.
    var low = 0;
    var high = starts.length - 1;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (topOf(middle) < -_state.widget.style.fontSize! * 2) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }

    for (var line = low; line < starts.length; line++) {
      final top = topOf(line);
      if (top > size.height) {
        break;
      }
      final painter = TextPainter(
        text: TextSpan(text: '${line + 1}', style: _state.widget.style),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        Offset(size.width - _kGutterPadding - painter.width, top),
      );
    }
  }

  @override
  bool shouldRepaint(_GutterPainter oldDelegate) => true;
}
