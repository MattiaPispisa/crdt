import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:greyhound_markdown_client/src/services/awareness_service.dart';
import 'package:greyhound_markdown_client/src/services/sync_client.dart';

/// Connection indicator plus one chip per connected peer.
class StatusBar extends StatelessWidget {
  const StatusBar({required this.status, required this.peers, super.key});

  final ValueListenable<SyncStatus> status;
  final ValueListenable<Map<String, PeerState>> peers;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            ValueListenableBuilder<SyncStatus>(
              valueListenable: status,
              builder: (context, value, _) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.circle,
                    size: 10,
                    color: switch (value) {
                      SyncStatus.connected => Colors.green,
                      SyncStatus.connecting ||
                      SyncStatus.reconnecting => Colors.orange,
                      SyncStatus.disconnected => Colors.red,
                    },
                  ),
                  const SizedBox(width: 6),
                  Text(switch (value) {
                    SyncStatus.connected => 'Connected',
                    SyncStatus.connecting => 'Connecting…',
                    SyncStatus.reconnecting => 'Reconnecting…',
                    SyncStatus.disconnected => 'Disconnected',
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
