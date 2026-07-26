import 'package:crdt_socket_sync/web_socket_relay_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:greyhound_markdown_client/src/services/awareness_service.dart';

/// Connection indicator plus one chip per connected peer.
class StatusBar extends StatelessWidget {
  const StatusBar({required this.status, required this.peers, super.key});

  final ValueListenable<ConnectionStatus> status;
  final ValueListenable<Map<String, PeerState>> peers;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            ValueListenableBuilder<ConnectionStatus>(
              valueListenable: status,
              builder: (context, value, _) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.circle,
                    size: 10,
                    color: switch (value) {
                      ConnectionStatus.connected => Colors.green,
                      ConnectionStatus.connecting ||
                      ConnectionStatus.reconnecting => Colors.orange,
                      ConnectionStatus.disconnected ||
                      ConnectionStatus.error => Colors.red,
                    },
                  ),
                  const SizedBox(width: 6),
                  Text(switch (value) {
                    ConnectionStatus.connected => 'Connected',
                    ConnectionStatus.connecting => 'Connecting…',
                    ConnectionStatus.reconnecting => 'Reconnecting…',
                    ConnectionStatus.disconnected => 'Disconnected',
                    ConnectionStatus.error => 'Connection error',
                  }),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ValueListenableBuilder<Map<String, PeerState>>(
                valueListenable: peers,
                builder: (context, value, _) => Wrap(
                  spacing: 6,
                  children: [
                    for (final peer in value.values)
                      Chip(
                        avatar: CircleAvatar(backgroundColor: peer.color),
                        label: Text(peer.name),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
