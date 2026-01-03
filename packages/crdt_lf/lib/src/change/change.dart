import 'package:crdt_lf/crdt_lf.dart';
import 'package:hlc_dart/hlc_dart.dart';

/// Change implementation for CRDT
///
/// A Change represents a modification to the CRDT state.
/// It includes an operation ID, dependencies, timestamp, author, and payload.
class Change {
  /// Creates a new [Change] with the given properties
  ///
  /// [id] the operation id of the change
  /// [operation] the operation that is being applied
  /// [deps] the dependencies of the change
  /// ([OperationId]s that this change depends on)
  /// [author] the author of the change
  factory Change({
    required OperationId id,
    required Operation operation,
    required Set<OperationId> deps,
    required PeerId author,
  }) {
    return Change.fromPayload(
      id: id,
      deps: deps,
      author: author,
      payload: operation.toPayload(),
    );
  }

  /// Creates a new [Change] with the given properties
  ///
  /// [id] the operation id of the change
  /// [payload] the operation payload that is being applied
  /// [deps] the dependencies of the change
  /// ([OperationId]s that this change depends on)
  /// [author] the author of the change
  const Change.fromPayload({
    required this.id,
    required this.deps,
    required this.author,
    required this.payload,
  });

  /// Creates a Change from a JSON object
  factory Change.fromJson(Map<String, dynamic> json) {
    return Change.fromPayload(
      id: OperationId.parse(json['id'] as String),
      deps: (json['deps'] as List)
          .map((d) => OperationId.parse(d as String))
          .toSet(),
      author: PeerId.parse(json['author'] as String),
      payload: json['payload'] as Map<String, dynamic>,
    );
  }

  /// The unique identifier for this change
  final OperationId id;

  /// The dependencies of this change
  /// ([OperationId]s that this change depends on)
  final Set<OperationId> deps;

  /// The timestamp when this change was created
  HybridLogicalClock get hlc => id.hlc;

  /// The peer that created this change
  final PeerId author;

  /// The payload of this change (the actual data modification)
  final Map<String, dynamic> payload;

  /// Serializes this change to a JSON object
  Map<String, dynamic> toJson() {
    return {
      'id': id.toString(),
      'deps': deps.map((d) => d.toString()).toList(),
      'author': author.toString(),
      'payload': payload,
    };
  }

  /// Returns a string representation of this change
  @override
  String toString() {
    final depsStr = deps.map((d) => d.toString()).join(', ');
    return 'Change(id: $id, deps: [$depsStr], '
        'hlc: $hlc, author: $author, payload: $payload)';
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
        author,
        payload,
      );
}

/// Utilities on [List] of [Change]s
extension ChangeList on List<Change> {
  /// Sort changes first by hlc then for author.
  ///
  /// If [inplace] is `true`, the list is sorted in place.
  /// Otherwise, a new list is returned.
  List<Change> sorted({
    bool inplace = false,
  }) {
    if (inplace) {
      sort(_hlcCompare);
      return this;
    }

    return List.from(this)..sort(_hlcCompare);
  }

  int _hlcCompare(Change a, Change b) {
    final hlcCompare = a.hlc.compareTo(b.hlc);
    if (hlcCompare != 0) {
      return hlcCompare;
    }
    return a.author.compareTo(b.author);
  }
}

/// Utilities on [Iterable] of [Change]s
extension ChangeIterable on Iterable<Change> {
  /// {@template change_iterable_newer_than}
  /// Returns the changes that are newer than the given [versionVector].
  ///
  /// A change is considered newer if its clock is strictly greater than the
  /// clock in the provided version vector for the same peer, or if the peer is
  /// not present in the provided vector.
  /// {@endtemplate}
  Iterable<Change> newerThan(VersionVector versionVector) {
    return where((change) {
      final hlc = versionVector[change.id.peerId];
      if (hlc == null) {
        return true;
      }
      return change.hlc.compareTo(hlc) > 0;
    });
  }
}
