import '../operation/id.dart';
import '../utils/set.dart';

/// [Frontiers] implementation for CRDT
///
/// [Frontiers] represent the latest operations in a [DAG].
/// They are used to efficiently track the latest state of the system.
class Frontiers {
  /// Creates a new empty [Frontiers]
  Frontiers() : _frontiers = {};

  /// Creates a new [Frontiers] with the given initial frontiers
  Frontiers.from(Iterable<OperationId> frontiers)
      : _frontiers = Set.from(frontiers);

  /// The set of [OperationId]s that form the [Frontiers]
  final Set<OperationId> _frontiers;

  /// Gets the current frontiers
  Set<OperationId> get() {
    return Set.from(_frontiers);
  }

  /// Updates the [Frontiers] with a new [OperationId]
  ///
  /// The [OperationId]'s dependencies are removed from the [Frontiers],
  /// and the [OperationId] itself is added to the [Frontiers].
  void update({
    required OperationId newOperationId,
    required Set<OperationId> oldDependencies,
  }) {
    // Remove all dependencies that are in the frontiers
    for (final dep in oldDependencies) {
      _frontiers.remove(dep);
    }

    // Add the new operation to the frontiers
    _frontiers.add(newOperationId);
  }

  /// Merges another [Frontiers] into this one
  ///
  /// The result is a new [Frontiers] that contains only the [OperationId]s
  /// that are not causally before any other [OperationId] in either [Frontiers].
  void merge(Frontiers other) {
    final result = <OperationId>{};

    // Add all operations from both frontiers
    final allOps = {..._frontiers, ...other._frontiers};

    // Filter out operations that are causally before other operations
    for (final op in allOps) {
      bool isFrontier = allOps.every(op.happenedAfterOrEqual);

      if (isFrontier) {
        result.add(op);
      }
    }

    _frontiers.clear();
    _frontiers.addAll(result);
  }

  /// Clears the [Frontiers]
  void clear() {
    _frontiers.clear();
  }

  /// Returns a string representation of the [Frontiers]
  @override
  String toString() {
    return _frontiers.map((f) => f.toString()).join(', ');
  }

  /// Compares two [Frontiers] for equality
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is Frontiers && setEquals(other._frontiers, _frontiers);
  }

  /// Returns a hash code for this [Frontiers]
  @override
  int get hashCode => Object.hashAll(_frontiers);

  /// Checks if the [Frontiers] are empty
  bool get isEmpty => _frontiers.isEmpty;

  /// Gets the number of operations in the frontiers
  int get length => _frontiers.length;

  /// Creates a copy of this [Frontiers]
  Frontiers copy() => Frontiers.from(_frontiers);
}
