// ignore_for_file: avoid_print just an example

import 'dart:async';
import 'dart:io';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_socket_sync/src/web_socket_client.dart';

import 'server_registry.dart';

void main(List<String> args) async {
  print('🚀 Starting CRDT WebSocket Client...');

  // Create a unique peer ID for this client
  final author = PeerId.generate();
  print('🆔 Client Peer ID: $author');

  // get a local CRDT document
  final document = getServerRegistryDocument();

  // Create a WebSocket client
  final client = WebSocketClient(
    url: 'ws://localhost:8080',
    document: document,
    author: author,
  );

  // Handle graceful shutdown
  ProcessSignal.sigint.watch().listen((signal) async {
    print('\n⏹️  Received SIGINT, shutting down gracefully...');
    await client.disconnect();
    client.dispose();
    print('✅ Client stopped.');
    exit(0);
  });

  // Listen to connection status changes
  client.connectionStatus.listen((status) {
    switch (status) {
      case ConnectionStatus.connected:
        print('🟢 Connected to server');
        break;
      case ConnectionStatus.disconnected:
        print('🔴 Disconnected from server');
        break;
      case ConnectionStatus.reconnecting:
        print('🟡 Reconnecting to server...');
        break;
      case ConnectionStatus.error:
        print('❌ Connection error');
        break;
    }
  });

  // Listen to incoming messages
  client.messages.listen((message) {
    print('📨 Received message: $message');
  });

  try {
    // Connect to the server
    print('🔗 Connecting to ws://localhost:8080...');
    final connected = await client.connect();

    if (connected) {
      print('✅ Successfully connected to server!');
      print('💡 Press Ctrl+C to stop the client');
      print('🎮 Starting interactive demo...');

      // Start the interactive demo
      await _runInteractiveDemo(document);
    } else {
      print('❌ Failed to connect to server');
      exit(1);
    }
  } catch (e) {
    print('❌ Error: $e');
    exit(1);
  }
}

/// Runs an interactive demo that creates CRDT operations periodically
Future<void> _runInteractiveDemo(CRDTDocument document) async {
  // Register a simple list handler for demonstration
  final listHandler = CRDTListHandler<String>(document, 'demo_list');
  document.registerHandler(listHandler);

  print('📝 Registered CRDT handlers: list');

  var counter = 0;

  // Create a timer that performs operations every 3 seconds
  Timer.periodic(const Duration(seconds: 3), (timer) {
    counter++;

    // Perform list operations
    final value = 'Item $counter';
    listHandler.insert(listHandler.length, value);

    // Occasionally delete items to show both operations
    if (counter % 5 == 0 && listHandler.length > 3) {
      listHandler.delete(0, 1);
      print('➖ Removed first item from list (total: ${listHandler.length})');
      print('📋 Updated list: ${listHandler.value}');
    }

    // Every 10 operations, create a snapshot
    if (counter % 10 == 0) {
      final snapshot = document.takeSnapshot();
      print('📸 Created snapshot at operation $counter');
      print('📊 Snapshot version: ${snapshot.versionVector}');
    }
  });

  // Keep the client running indefinitely
  final completer = Completer<void>();
  return completer.future;
}
