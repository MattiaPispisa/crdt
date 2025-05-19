import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

typedef StrokeId = String;

@immutable
class Stroke {
  final StrokeId id;
  final List<Offset> points;
  final Color color;
  final double width;

  const Stroke({
    required this.id,
    required this.points,
    required this.color,
    required this.width,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is Stroke &&
        other.id == id &&
        other.color == color &&
        other.width == width &&
        listEquals(other.points, points);
  }

  @override
  int get hashCode => Object.hash(id, points, color, width);

  Stroke copyWith({List<Offset>? points, Color? color, double? strokeWidth}) {
    return Stroke(
      id: id,
      points: points ?? this.points,
      color: color ?? this.color,
      width: strokeWidth ?? width,
    );
  }

  @override
  String toString() {
    return 'Stroke(id: $id, points: $points, color: $color, strokeWidth: $width)';
  }
}
