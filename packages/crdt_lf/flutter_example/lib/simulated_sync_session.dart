import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter_example/shared/network.dart';
import 'package:shared_examples_infrastructure/shared_examples_infrastructure.dart';

/// An [ExampleSyncSession] backed by the simulated in-memory [Network].
///
/// Owns a fresh [CRDTDocument] for [author] and wires it to the shared network
/// bus: local changes are broadcast, remote changes (from the other peer) are
/// applied. The bus preserves send order, so applied changes are always
/// causally ready.
class SimulatedSyncSession implements ExampleSyncSession {
  /// Creates a simulated session for [author] on [network].
  SimulatedSyncSession({
    required PeerId author,
    required Network network,
    required this.label,
  }) : document = CRDTDocument(peerId: author),
       _network = network {
    _remote = _network.stream(document.peerId).listen((change) {
      document.applyChange(change);
    });
    _local = document.localChanges.listen(_network.sendChange);
  }

  @override
  final CRDTDocument document;

  @override
  final String label;

  final Network _network;
  late final StreamSubscription<Change> _remote;
  late final StreamSubscription<Change> _local;

  @override
  void dispose() {
    _remote.cancel();
    _local.cancel();
    document.dispose();
  }
}
