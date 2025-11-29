import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'stroke.dart';

class WhiteboardPainter extends CustomPainter {
  WhiteboardPainter({required this.strokes});

  List<Stroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    // Draw the background
    _drawGrid(canvas, size);

    // Draw the strokes
    for (final stroke in strokes) {
      final points = stroke.points;

      if (points.isEmpty) continue;
      final paint = stroke.getPaint();

      if (stroke.points.length == 1) {
        paint.style = PaintingStyle.fill;
        final center = stroke.points.first;
        final radius = stroke.width / 2;
        canvas.drawCircle(center, radius, paint);
        continue;
      }

      final path = stroke.toPath();
      canvas.drawPath(path, paint);
    }
  }

  void _drawGrid(Canvas canvas, Size size) {
    const gridStrokeWidth = 1.0;
    final gridSpacing = size.width / 32;

    final gridPaint =
        Paint()
          ..color = Colors.grey.shade500
          ..strokeWidth = gridStrokeWidth;

    // Horizontal lines for main grid
    for (double y = 0; y <= size.height; y += gridSpacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Vertical lines for main grid
    for (double x = 0; x <= size.width; x += gridSpacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) =>
      !listEquals((oldDelegate as WhiteboardPainter).strokes, strokes);
}

extension _StrokeX on Stroke {
  Paint getPaint() {
    return Paint()
      ..color = color
      ..strokeWidth = max(1.0, width)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
  }

  Path toPath() {
    final path = Path();

    // Add the first point to the path
    final firstPoint = points.first;
    path.moveTo(firstPoint.dx, firstPoint.dy);

    // Add subsequent points using quadratic Bezier curves
    for (int i = 1; i < points.length - 1; i++) {
      final p1 = points[i];
      final p2 = points[i + 1];

      path.quadraticBezierTo(
        p1.dx,
        p1.dy,
        (p1.dx + p2.dx) / 2,
        (p1.dy + p2.dy) / 2,
      );
    }

    return path;
  }
}
