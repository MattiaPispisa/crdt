import 'package:crdt_socket_sync/client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_example/todo_list/_state.dart';

class ConnectionStatusIndicator extends StatelessWidget {
  const ConnectionStatusIndicator({super.key, required this.state});

  final TodoListState state;

  Color color(ConnectionStatus connectionStatus) => switch (connectionStatus) {
    ConnectionStatus.connected => Colors.green,
    ConnectionStatus.disconnected => Colors.grey,
    ConnectionStatus.reconnecting => Colors.yellow,
    ConnectionStatus.connecting => Colors.blue,
    ConnectionStatus.error => Colors.red,
  };

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      height: 40,
      color: color(state.connectionStatusValue),
      child:
          state.connectionStatusValue.isError ||
                  state.connectionStatusValue.isDisconnected
              ? _reconnectButton(context)
              : null,
    );
  }

  Widget _reconnectButton(BuildContext context) {
    return Center(
      child: IconButton(
        icon: const Icon(Icons.refresh),
        color: Colors.white,
        onPressed: () {
          state.connect();
        },
      ),
    );
  }
}
