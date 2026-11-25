// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf_devtools_extension/src/application/changes/row_graph.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

/// Draws the lane graph of one row: a line per active lane, a dot on the
/// lane of the change, and a curve from each merged lane to the dot.
class LaneGraphPainter extends CustomPainter {
  const LaneGraphPainter({
    required this.row,
    required this.colors,
    required this.olderAbove,
  });

  /// The width of one lane.
  static const double laneWidth = 14;

  final RowGraph row;

  /// The color of each lane.
  final List<Color> colors;

  /// Whether the older changes are above this row; a merge curve starts
  /// from the side of the older changes.
  final bool olderAbove;

  @override
  void paint(Canvas canvas, Size size) {
    double x(int lane) => lane * laneWidth + laneWidth / 2;
    final mid = size.height / 2;
    final stroke =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
    for (final lane in row.active) {
      stroke.color = colors[lane];
      canvas.drawLine(Offset(x(lane), 0), Offset(x(lane), size.height), stroke);
    }
    final dot = Offset(x(row.lane), mid);
    final edge = olderAbove ? 0.0 : size.height;
    for (final lane in row.mergesFrom) {
      stroke.color = colors[lane];
      canvas.drawPath(
        Path()
          ..moveTo(x(lane), edge)
          ..quadraticBezierTo(x(lane), mid, dot.dx, dot.dy),
        stroke,
      );
    }
    canvas.drawCircle(dot, 3.5, Paint()..color = colors[row.lane]);
  }

  @override
  bool shouldRepaint(LaneGraphPainter old) =>
      old.row != row ||
      old.olderAbove != olderAbove ||
      !listEquals(old.colors, colors);
}
