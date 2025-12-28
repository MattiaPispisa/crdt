import 'package:crdt_lf/crdt_lf.dart';
import 'package:hlc_dart/hlc_dart.dart';

/// Tag for OR-based handlers entries,
/// combining HLC and PeerId for proper ordering.
///
/// Comparison is done first by [HybridLogicalClock] (causal order),
/// then by [PeerId] (deterministic).
class ORHandlerTag implements Comparable<ORHandlerTag> {
  /// Creates an OR-based handler tag
  const ORHandlerTag({
    required this.hlc,
    required this.peerId,
  });

  /// Parses a tag from string format "peerId@hlc"
  factory ORHandlerTag.parse(String tag) {
    final parts = tag.split('@');
    if (parts.length != 2) {
      throw FormatException('Invalid ORHandlerTag format: $tag');
    }
    return ORHandlerTag(
      peerId: PeerId.parse(parts[0]),
      hlc: HybridLogicalClock.parse(parts[1]),
    );
  }

  /// The HLC timestamp
  final HybridLogicalClock hlc;

  /// The peer ID
  final PeerId peerId;

  @override
  int compareTo(ORHandlerTag other) {
    // First compare by HLC (causal order)
    final hlcComparison = hlc.compareTo(other.hlc);
    if (hlcComparison != 0) {
      return hlcComparison;
    }
    // If HLC is equal, compare by PeerId (deterministic)
    return peerId.compareTo(other.peerId);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is ORHandlerTag && other.hlc == hlc && other.peerId == peerId;
  }

  @override
  int get hashCode => Object.hash(hlc, peerId);

  @override
  String toString() => '$peerId@$hlc';
}
