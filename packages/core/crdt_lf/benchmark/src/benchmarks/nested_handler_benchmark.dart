import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:crdt_lf/crdt_lf.dart';

import '../common/custom_emitter.dart';

/// Builds a nested tree on [doc]: a [CRDTListRefHandler] root holding [width]
/// text leaves, each carrying one short insert. Returns the root.
///
/// Total handlers = `width + 1`; total changes ≈ `2 * width`
/// (one `insertRef` per leaf + one `insert` per leaf).
CRDTListRefHandler _buildTree(CRDTDocument doc, int width) {
  final root = CRDTListRefHandler(doc, 'root');
  for (var i = 0; i < width; i++) {
    final leaf = CRDTFugueTextHandler(doc, doc.newHandlerId())
      ..insert(0, 'item $i');
    root.insertRef(i, leaf);
  }
  return root;
}

/// Resolves the whole nested tree with **cold caches**.
///
/// Every handler recomputes its state by scanning the document oplog, so this
/// exposes how resolution scales with the number of nested handlers (each of
/// the `width + 1` handlers scans all `~2 * width` changes).
class NestedResolveBenchmark extends BenchmarkBase {
  /// Creates a resolve benchmark for a tree with [width] leaves.
  NestedResolveBenchmark(this.width)
      : super(
          'Resolve nested tree with $width leaves (cold caches)',
          emitter: const CustomEmitter(),
        );

  /// The number of leaves in the tree.
  final int width;
  late final CRDTDocument _doc;
  late final CRDTListRefHandler _root;

  @override
  void setup() {
    _doc = CRDTDocument(peerId: PeerId.generate());
    _root = _buildTree(_doc, width);
  }

  @override
  void run() {
    // Drop every handler cache so the whole tree is recomputed from the oplog.
    for (final handler in _doc.registeredHandlers.values) {
      handler.invalidateCache();
    }
    final resolved = _root.resolved;
    if (resolved.length != width) {
      throw StateError('unexpected resolved length: ${resolved.length}');
    }
  }
}

/// Models a fresh peer opening a synced nested document: build the changes
/// once, then on every run import them into a brand-new document (factories
/// registered) and resolve the whole tree.
///
/// Measures the realistic end-to-end cost of reconstructing and reading a
/// nested document received only as a list of changes.
class NestedReconstructBenchmark extends BenchmarkBase {
  /// Creates an import + resolve benchmark for a tree with [width] leaves.
  NestedReconstructBenchmark(this.width)
      : super(
          'Import + resolve nested tree with $width leaves (fresh peer)',
          emitter: const CustomEmitter(),
        );

  /// The number of leaves in the tree.
  final int width;
  late final List<Change> _changes;

  @override
  void setup() {
    final doc = CRDTDocument(peerId: PeerId.generate());
    _buildTree(doc, width);
    _changes = doc.exportChanges();
  }

  @override
  void run() {
    final doc = CRDTDocument(peerId: PeerId.generate())
      ..registerDefaultFactories();
    final root = CRDTListRefHandler(doc, 'root');
    doc.importChanges(_changes);
    final resolved = root.resolved;
    if (resolved.length != width) {
      throw StateError('unexpected resolved length: ${resolved.length}');
    }
  }
}

void main() {
  for (final width in [50, 200, 800]) {
    NestedResolveBenchmark(width).report();
  }
  for (final width in [50, 200, 800]) {
    NestedReconstructBenchmark(width).report();
  }
}
