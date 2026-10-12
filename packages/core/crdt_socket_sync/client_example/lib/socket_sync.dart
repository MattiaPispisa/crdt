import 'dart:async';
import 'dart:math';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/web_socket_client.dart';
import 'package:en_logger/en_logger.dart';
import 'package:factory_example/factory_example.dart';
import 'package:flutter/material.dart';
import 'package:hive/hive.dart';

const _kUrlKey = 'url';
const _kNameKey = 'name';

/// One peer, this device, synced with a `crdt_socket_sync` server.
///
/// The server URL and the display name are stored in the `settings` box,
/// and the settings dialog edits them.
class SocketSync extends ExampleSync {
  /// Creates the sync; [compressor] has to match the server's.
  SocketSync({
    required Box<String> settings,
    required String defaultUrl,
    required EnLogger logger,
    Compressor? compressor,
  }) : _settings = settings,
       _defaultUrl = defaultUrl,
       _defaultName = 'user_${Random().nextInt(1000000)}',
       _logger = logger,
       _compressor = compressor;

  final Box<String> _settings;
  final String _defaultUrl;
  final String _defaultName;
  final EnLogger _logger;
  final Compressor? _compressor;

  /// The server URL.
  String get url => _settings.get(_kUrlKey) ?? _defaultUrl;

  /// The display name sent in the awareness state.
  String get name => _settings.get(_kNameKey) ?? _defaultName;

  /// Stores [url] and [name] for the next opened example.
  Future<void> save({required String url, required String name}) async {
    await _settings.put(_kUrlKey, url);
    await _settings.put(_kNameKey, name);
  }

  @override
  final List<ExamplePeer> peers = const [
    ExamplePeer(key: 'device', label: 'This device'),
  ];

  @override
  CRDTSocketClient createClient(CRDTDocument document, ExamplePeer peer) {
    final client = WebSocketClient(
      url: url,
      document: document,
      author: document.peerId,
      // The demo servers run the awareness plugin, so the client must too:
      // otherwise it cannot decode the awareness messages the server sends.
      plugins: [
        ClientAwarenessPlugin(
          initialMetadata: {'name': name},
          throttleDuration: const Duration(milliseconds: 100),
        ),
      ],
      // Symmetric: it has to match the server's compressor.
      compressor: _compressor,
    );
    // Nothing is retried: logging is all this example does with a fault.
    client.faults.listen((fault) {
      _logger.error('${fault.reason}: ${fault.error}');
    });
    return client;
  }

  @override
  Widget buildSettings(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.settings),
      tooltip: 'Server settings',
      onPressed:
          () => unawaited(
            showDialog<void>(
              context: context,
              builder: (_) => _SocketSettingsDialog(sync: this),
            ),
          ),
    );
  }
}

class _SocketSettingsDialog extends StatefulWidget {
  const _SocketSettingsDialog({required this.sync});

  final SocketSync sync;

  @override
  State<_SocketSettingsDialog> createState() => _SocketSettingsDialogState();
}

class _SocketSettingsDialogState extends State<_SocketSettingsDialog> {
  late final TextEditingController _url;
  late final TextEditingController _name;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: widget.sync.url);
    _name = TextEditingController(text: widget.sync.name);
  }

  @override
  void dispose() {
    _url.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await widget.sync.save(url: _url.text.trim(), name: _name.text.trim());
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Server settings'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _url,
            decoration: const InputDecoration(
              icon: Icon(Icons.link),
              labelText: 'Server URL',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              icon: Icon(Icons.person),
              labelText: 'Display name',
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Applies to the next example you open.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
