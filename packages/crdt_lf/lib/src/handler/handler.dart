import 'package:crdt_lf/crdt_lf.dart';

/// Abstract class for CRDT handlers
///
/// A handler is a component that manages the state of a specific
/// data structure in the CRDT system.
abstract class Handler<T> with SnapshotProvider {
  /// Creates a new handler for the given document
  Handler(this.doc) {
    doc.registerHandler(this);
  }

  /// The document that owns this handler
  final CRDTDocument doc;

  /// The ID of the handler
  @override
  String get id;

  /// The cached state of the handler
  T? _cachedState;

  /// The version at which the cached state was computed
  Set<OperationId>? _cachedVersion;

  /// Returns the cached state
  T? get cachedState {
    if (_cachedState != null && setEquals(_cachedVersion, doc.version)) {
      return _cachedState;
    }

    return null;
  }

  /// Updates the cached state
  void updateCachedState(T cachedState) {
    _cachedState = cachedState;
    _cachedVersion = Set.from(doc.version);
  }

  /// Invalidates the cached state
  void invalidateCache() {
    _cachedState = null;
    _cachedVersion = null;
  }
}
