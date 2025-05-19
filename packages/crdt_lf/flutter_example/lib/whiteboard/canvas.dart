import 'package:flutter/material.dart';
import 'stroke.dart';

class WhiteboardPainter extends CustomPainter {
  final List<Stroke> strokes;

  WhiteboardPainter({required this.strokes});

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;

    for (final stroke in strokes) {
      paint.color = stroke.color;
      paint.strokeWidth = stroke.width;

      if (stroke.points.isNotEmpty) {
        final path = Path();
        path.moveTo(stroke.points.first.dx, stroke.points.first.dy);
        for (var i = 1; i < stroke.points.length; i++) {
          path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
        }
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant WhiteboardPainter oldDelegate) {
    return oldDelegate.strokes != strokes;
  }
}
