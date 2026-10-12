import 'dart:async';

import 'package:crdt_lf_flutter_example/simulated/network.dart';
import 'package:flutter/material.dart';

/// A compact network status with a button that opens the
/// [_NetworkSettingsDialog].
///
/// Lets the user tune the simulated connection: sync on/off, random delay and
/// its semantic latency level.
class NetworkSettings extends StatelessWidget {
  /// Creates the settings control of [network].
  const NetworkSettings({required this.network, super.key});

  /// The simulated network to tune.
  final SimulatedNetwork network;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: network,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              network.isOnline ? Icons.cloud_done : Icons.cloud_off,
              size: 18,
            ),
            const SizedBox(width: 6),
            Text(network.isOnline ? 'Online' : 'Offline'),
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Network settings',
              onPressed: () => _openSettings(context),
            ),
          ],
        );
      },
    );
  }

  void _openSettings(BuildContext context) {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => _NetworkSettingsDialog(network: network),
      ),
    );
  }
}

class _NetworkSettingsDialog extends StatelessWidget {
  const _NetworkSettingsDialog({required this.network});

  final SimulatedNetwork network;

  @override
  Widget build(BuildContext context) {
    // Rebuild on every network change so the controls stay in sync regardless
    // of where in the tree the dialog is mounted.
    return ListenableBuilder(
      listenable: network,
      builder: (context, _) {
        final online = network.isOnline;
        final delayEnabled = online && network.randomDelay;
        return AlertDialog(
          title: const Text('Network settings'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Sync'),
                subtitle: const Text('Broadcast changes between peers'),
                value: online,
                onChanged: network.setOnlineStatus,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Random delay'),
                subtitle: const Text(
                  'Simulate connection latency with a random delay',
                ),
                value: network.randomDelay,
                onChanged: online ? network.setRandomDelay : null,
              ),
              const SizedBox(height: 8),
              Text(
                'Latency',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: delayEnabled ? null : Theme.of(context).disabledColor,
                ),
              ),
              const SizedBox(height: 4),
              SegmentedButton<DelayLevel>(
                segments: [
                  for (final level in DelayLevel.values)
                    ButtonSegment<DelayLevel>(
                      value: level,
                      label: Text(level.label),
                    ),
                ],
                selected: {network.delayLevel},
                onSelectionChanged:
                    delayEnabled
                        ? (selection) => network.setDelayLevel(selection.first)
                        : null,
              ),
              const SizedBox(height: 4),
              Text(
                'Each change is delayed by a random value up to '
                '${network.delayLevel.upperBoundMs} ms.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}
