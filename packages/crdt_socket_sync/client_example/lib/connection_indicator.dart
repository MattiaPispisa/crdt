import 'package:crdt_socket_sync/client.dart';
import 'package:flutter/material.dart';

/// App-bar indicator that reflects the live [CRDTSocketClient.connectionStatus].
class ConnectionIndicator extends StatelessWidget {
  /// Creates a connection indicator for [client].
  const ConnectionIndicator({super.key, required this.client});

  /// The client whose connection status is shown.
  final CRDTSocketClient client;

  ({Color color, IconData icon, String label}) _visual(
    ConnectionStatus status,
  ) {
    switch (status) {
      case ConnectionStatus.connected:
        return (
          color: Colors.green,
          icon: Icons.cloud_done,
          label: 'Connected',
        );
      case ConnectionStatus.connecting:
        return (
          color: Colors.orange,
          icon: Icons.cloud_sync,
          label: 'Connecting',
        );
      case ConnectionStatus.reconnecting:
        return (
          color: Colors.orange,
          icon: Icons.cloud_sync,
          label: 'Reconnecting',
        );
      case ConnectionStatus.disconnected:
        return (
          color: Colors.grey,
          icon: Icons.cloud_off,
          label: 'Disconnected',
        );
      case ConnectionStatus.error:
        return (color: Colors.red, icon: Icons.cloud_off, label: 'Error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ConnectionStatus>(
      stream: client.connectionStatus,
      initialData: client.connectionStatusValue,
      builder: (context, snapshot) {
        final status = snapshot.data ?? ConnectionStatus.disconnected;
        final visual = _visual(status);

        // Once the automatic reconnects are exhausted (error) or the client is
        // disconnected, offer a manual retry: tapping re-runs connect().
        final canRetry =
            status == ConnectionStatus.disconnected ||
            status == ConnectionStatus.error;

        return IconButton(
          icon: Icon(visual.icon, color: visual.color),
          tooltip:
              canRetry ? '${visual.label} — tap to reconnect' : visual.label,
          onPressed: canRetry ? () => client.connect() : null,
        );
      },
    );
  }
}
