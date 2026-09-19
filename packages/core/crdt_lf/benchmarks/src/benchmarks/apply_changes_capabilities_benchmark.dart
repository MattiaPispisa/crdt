import 'package:benchmark_infrastructure/benchmark_infrastructure.dart';
import 'package:crdt_lf/crdt_lf.dart';

/// The apply path of a document that also keeps track of what its data needs.
///
/// `ApplyChangesBenchmark` measures a document nobody asks about capabilities,
/// where the fold never runs. A server does ask — it snapshots, and it answers
/// a handshake — so from then on every change it applies passes the fold. That
/// is the path this measures, and the apply path is the one place the document
/// is careful never to decode an operation envelope.
class ApplyChangesWithCapabilitiesBenchmark extends TimedBenchmarkBase {
  ApplyChangesWithCapabilitiesBenchmark()
      : super('Apply 1000 changes (capabilities tracked)');

  late final List<Change> changes;

  @override
  void setup() {
    final doc = CRDTDocument(peerId: PeerId.generate());
    final list = CRDTListHandler<String>(
      doc,
      'list',
      handlerType: 'CRDTListHandler<String>',
    );
    for (var i = 0; i < 1000; i++) {
      list.insert(i, 'item $i');
    }
    changes = doc.exportChanges();
  }

  @override
  void run() {
    CRDTDocument(peerId: PeerId.generate())
      // Asking once is what a server does, and it is what turns the fold on
      // for every change that follows.
      ..describeDataRequirements()
      ..importChanges(changes);
  }
}

void main() {
  ApplyChangesWithCapabilitiesBenchmark().report();
}
