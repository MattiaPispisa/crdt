import 'package:crdt_lf/crdt_lf.dart';

/// Abstract class for CRDT handlers
///
/// A handler is a component that manages the state of a specific
/// data structure in the CRDT system.
abstract class Handler<T>
    with DocumentConsumer, SnapshotProvider, CacheableStateProvider<T> {
  /// Creates a new handler for the given document
  Handler(this.doc) {
    doc.registerHandler(this);
  }

  /// The document that owns this handler
  final CRDTDocument doc;
}
