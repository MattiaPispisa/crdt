/// Change implementation for CRDT
///
/// A Change represents a modification to the CRDT state.
/// It includes an operation ID, dependencies, timestamp, author, and payload.

import 'package:crdt_lf/src/operation/operation.dart';
import 'package:hlc_dart/hlc_dart.dart';

import '../operation/id.dart';
import '../peer_id.dart';
import '../utils/set.dart';

/// A change to the CRDT state
class Change {
  /// Creates a new [Change] with the given properties
  const Change._({
    required this.id,
    required this.deps,
    required this.hlc,
    required this.author,
    required this.payload,
  });

  /// Creates a new [Change] with the given properties
  ///
  /// [id] the operation id of the change
  /// [operation] the operation that is being applied
  /// [deps] the dependencies of the change ([OperationId]s that this change depends on)
  /// [hlc] the hybrid logical clock of the change
  /// [author] the author of the change
  factory Change({
    required OperationId id,
    required Operation operation,
    required Set<OperationId> deps,
    required HybridLogicalClock hlc,
    required PeerId author,
  }) {
    return Change._(
      id: id,
      deps: deps,
      hlc: hlc,
      author: author,
      payload: operation.toPayload(),
    );
  }

  /// Creates a Change from a JSON object
  static Change fromJson(Map<String, dynamic> json) {
    return Change._(
      id: OperationId.parse(json['id'] as String),
      deps: (json['deps'] as List)
          .map((d) => OperationId.parse(d as String))
          .toSet(),
      hlc: HybridLogicalClock(
        l: json['hlc']['l'] as int,
        c: json['hlc']['c'] as int,
      ),
      author: PeerId.parse(json['author'] as String),
      payload: json['payload'],
    );
  }

  /// The unique identifier for this change
  final OperationId id;

  /// The dependencies of this change ([OperationId]s that this change depends on)
  final Set<OperationId> deps;

  /// The timestamp when this change was created
  final HybridLogicalClock hlc;

  /// The peer that created this change
  final PeerId author;

  /// The payload of this change (the actual data modification)
  final dynamic payload;

  /// Serializes this change to a JSON object
  Map<String, dynamic> toJson() {
    return {
      'id': id.toString(),
      'deps': deps.map((d) => d.toString()).toList(),
      'hlc': {
        'l': hlc.l,
        'c': hlc.c,
      },
      'author': author.toString(),
      'payload': payload,
    };
  }

  /// Returns a string representation of this change
  @override
  String toString() {
    final depsStr = deps.map((d) => d.toString()).join(', ');
    return 'Change(id: $id, deps: [$depsStr], hlc: $hlc, author: $author, payload: $payload)';
  }

  /// Compares two Changes for equality
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is Change &&
        other.id == id &&
        setEquals(other.deps, deps) &&
        other.hlc == hlc &&
        other.author == author &&
        other.payload == payload;
  }

  /// Returns a hash code for this Change
  @override
  int get hashCode => Object.hash(
        id,
        Object.hashAll(deps),
        hlc,
        author,
        payload,
      );
}

/// Utilities on [List] of [Change]s
extension ChangeList on List<Change> {
  /// Sort changes first by hlc then for author
  List<Change> sorted() {
    return List.from(this)
      ..sort((a, b) {
        final hlcCompare = a.hlc.compareTo(b.hlc);
        if (hlcCompare != 0) {
          return hlcCompare;
        }
        return a.author.compareTo(b.author);
      });
  }
}
