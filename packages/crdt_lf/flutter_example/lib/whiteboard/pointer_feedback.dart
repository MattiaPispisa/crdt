import 'package:crdt_lf/crdt_lf.dart';
import 'package:flutter/material.dart';

@immutable
class PointerFeedback {
  const PointerFeedback({
    required this.offset,
    required this.color,
    required this.peerId,
  });

  final Offset offset;
  final Color color;
  final PeerId peerId;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PointerFeedback &&
        other.offset == offset &&
        other.color == color &&
        other.peerId == peerId;
  }

  @override
  int get hashCode => Object.hash(offset, color, peerId);

  PointerFeedback copyWith({Offset? offset, Color? color}) {
    return PointerFeedback(
      offset: offset ?? this.offset,
      color: color ?? this.color,
      peerId: peerId,
    );
  }
}
