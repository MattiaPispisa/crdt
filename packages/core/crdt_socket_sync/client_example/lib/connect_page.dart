import 'package:flutter/material.dart';
import 'package:crdt_socket_sync_client_example/user/_state.dart';
import 'package:crdt_socket_sync_client_example/widgets/custom_form_field.dart';
import 'package:provider/provider.dart';

/// Entry screen: pick the server URL (and a display name), then open the
/// examples. Each example connects to that URL on its own document.
class ConnectPage extends StatelessWidget {
  /// Creates the connect page.
  const ConnectPage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.read<UserState>();
    return Scaffold(
      appBar: AppBar(title: const Text('CRDT Socket Sync')),
      body: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Connect to a crdt_socket_sync server, then open the '
                    'examples. Open several windows to collaborate live.',
                    textAlign: TextAlign.center,
                  ),
                ),
                CustomFormField(
                  label: 'Server URL',
                  initialValue: user.url,
                  icon: Icons.link,
                  onChanged: user.setUrl,
                ),
                CustomFormField(
                  label: 'Display name',
                  initialValue: user.username,
                  icon: Icons.person,
                  onChanged: user.setUsername,
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton.icon(
                    onPressed:
                        () => Navigator.of(context).pushNamed('/examples'),
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('Open examples'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
