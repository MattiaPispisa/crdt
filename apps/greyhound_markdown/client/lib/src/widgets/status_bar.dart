import 'package:crdt_socket_sync/web_socket_relay_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:greyhound_markdown_client/src/l10n/l10n_extension.dart';
import 'package:greyhound_markdown_client/src/services/awareness/awareness_service.dart';

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
                      ConnectionStatus.error ||
                      ConnectionStatus.unsupported => Colors.red,
                    },
                  ),
                  const SizedBox(width: 6),
                  Text(switch (value) {
                    ConnectionStatus.connected => context.l10n.statusConnected,
                    ConnectionStatus.connecting =>
                      context.l10n.statusConnecting,
                    ConnectionStatus.reconnecting =>
                      context.l10n.statusReconnecting,
                    ConnectionStatus.disconnected =>
                      context.l10n.statusDisconnected,
                    ConnectionStatus.error => context.l10n.statusError,
                    ConnectionStatus.unsupported =>
                      context.l10n.statusUnsupported,
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
