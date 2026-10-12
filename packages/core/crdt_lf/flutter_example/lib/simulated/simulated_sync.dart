import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter_example/simulated/network.dart';
import 'package:crdt_lf_flutter_example/simulated/network_settings.dart';
import 'package:crdt_lf_flutter_example/simulated/text_presence_hub.dart';
import 'package:crdt_socket_sync/client.dart';
import 'package:factory_example/factory_example.dart';
import 'package:flutter/widgets.dart';

/// Two simulated peers in the same window, synced over a [SimulatedNetwork].
///
/// Text cursors cross the panes through a [TextPresenceHub] per document.
class SimulatedSync extends ExampleSync {
  /// Creates the sync over [network], or over a new offline one.
  SimulatedSync({SimulatedNetwork? network})
    : network = network ?? SimulatedNetwork(),
      _hubs = {};

  /// The network the settings control.
  final SimulatedNetwork network;

  final Map<String, TextPresenceHub> _hubs;

  @override
  final List<ExamplePeer> peers = const [
    ExamplePeer(key: 'peer_1', label: 'Peer 1'),
    ExamplePeer(key: 'peer_2', label: 'Peer 2'),
  ];

  @override
  CRDTSocketClient createClient(CRDTDocument document, ExamplePeer peer) {
    return SimulatedSocketClient(document: document, network: network);
  }

  @override
  TextCursorPresence textPresence(CRDTSocketClient client, ExamplePeer peer) {
    final hub = _hubs.putIfAbsent(
      client.document.documentId,
      TextPresenceHub.new,
    );
    return hub.register(peerId: client.author.toString(), label: peer.label);
  }

  @override
  Widget buildSettings(BuildContext context) =>
      NetworkSettings(network: network);
}
