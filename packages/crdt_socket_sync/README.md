# CRDT Socket Sync

A comprehensive Dart package for synchronizing Conflict-free Replicated Data Types (CRDTs) between multiple clients and a server.

## Overview

CRDT Socket Sync provides a robust, real-time synchronization system that allows multiple clients to collaborate on shared documents without conflicts. Built on top of [crdt_lf](https://pub.dev/packages/crdt_lf), this package enables seamless data synchronization with automatic conflict resolution.

## Features

- 🔄 **Real-time Synchronization**: Instant propagation of changes across all connected clients
- 🌐 **WebSocket Support**: Built-in WebSocket client and server implementations
- 🔧 **Conflict Resolution**: Automatic conflict-free merge of concurrent operations
- 📦 **Compression**: Optional data compression for efficient network usage
- 🔌 **Modular Architecture**: Separate client and server components with clean abstractions
- 📡 **Automatic Reconnection**: Robust connection handling with automatic retry logic
- 🎯 **Type Safety**: Full Dart type safety with generic document handlers
- 📊 **Event Monitoring**: Comprehensive event streams for connection and synchronization monitoring

## Installation

Add this package to your `pubspec.yaml`:

```yaml
dependencies:
  crdt_socket_sync: ^0.1.0
```

Then run:

```bash
dart pub get
```

## Quick Start

### Server Setup

```dart
import 'package:crdt_socket_sync/src/web_socket_server.dart';

void main() async {
  // Create a server registry to manage documents
  final registry = InMemoryServerRegistry();
  
  // Create and start the WebSocket server
  final server = WebSocketServer(
    host: 'localhost',
    port: 8080,
    serverRegistry: registry,
  );
  
  await server.start();
  print('Server started on localhost:8080');
  
  // Listen to server events
  server.serverEvents.listen((event) {
    print('Server event: ${event.type} - ${event.message}');
  });
}
```

### Client Setup

```dart
import 'package:crdt_socket_sync/src/web_socket_client.dart';
import 'package:crdt_lf/crdt_lf.dart';

void main() async {
  // Create a CRDT document
  final document = CRDTDocument.create(peerId: PeerId.generate());
  
  // Register handlers for different data types
  final listHandler = CRDTListHandler<String>(document, 'shared_list');
  document.registerHandler(listHandler);
  
  // Create the client
  final client = WebSocketClient(
    url: 'ws://localhost:8080',
    document: document,
    author: document.peerId,
  );
  
  // Monitor connection status
  client.connectionStatus.listen((status) {
    print('Connection status: $status');
  });
  
  // Connect to server
  final connected = await client.connect();
  if (connected) {
    print('Connected successfully!');
    
    // Make changes to the document
    listHandler.insert(0, 'Hello, World!');
  }
}
```

## Library Structure

The package is organized into several modules for different use cases:

### Import Options

#### For Client Applications
```dart
// Basic client interfaces
import 'package:crdt_socket_sync/src/client.dart';

// WebSocket client implementation
import 'package:crdt_socket_sync/src/web_socket_client.dart';
```

#### For Server Applications
```dart
// Basic server interfaces
import 'package:crdt_socket_sync/src/server.dart';

// WebSocket server implementation
import 'package:crdt_socket_sync/src/web_socket_server.dart';
```
## Advanced Usage

### Custom Document Registry

Implement your own document storage backend:

```dart
class CustomServerRegistry implements CRDTServerRegistry {
  final Map<String, CRDTDocument> _documents = {};
  
  @override
  CRDTDocument? getDocument(String documentId) {
    return _documents[documentId];
  }
  
  @override
  void setDocument(String documentId, CRDTDocument document) {
    _documents[documentId] = document;
  }
  
  @override
  List<String> get documentIds => _documents.keys.toList();
}
```

### Compression

Enable data compression for reduced bandwidth usage:

```dart
// Server with compression
final server = WebSocketServer(
  host: 'localhost',
  port: 8080,
  serverRegistry: registry,
  compressor: GzipCompressor(), // or your custom compressor
);

// Client with compression
final client = WebSocketClient(
  url: 'ws://localhost:8080',
  document: document,
  author: author,
  compressor: GzipCompressor(),
);
```

### Event Monitoring

Monitor detailed synchronization events:

```dart
// Server events
server.serverEvents.listen((event) {
  switch (event.type) {
    case ServerEventType.clientConnected:
      print('Client ${event.data?['clientId']} connected');
      break;
    case ServerEventType.clientDisconnected:
      print('Client ${event.data?['clientId']} disconnected');
      break;
    case ServerEventType.clientChangeApplied:
      print('Change applied from client');
      break;
  }
});

// Client messages
client.messages.listen((message) {
  switch (message.type) {
    case MessageType.change:
      print('Received change from server');
      break;
    case MessageType.snapshot:
      print('Received snapshot from server');
      break;
  }
});
```

## Protocol Details

The synchronization protocol includes:

- **Handshake**: Initial client-server negotiation with version exchange
- **Changes**: Real-time propagation of CRDT operations
- **Snapshots**: Full document state synchronization
- **Ping/Pong**: Connection health monitoring
- **Error Handling**: Graceful error recovery and reporting

## Error Handling

The library provides robust error handling with automatic recovery:

```dart
client.connectionStatus.listen((status) {
  switch (status) {
    case ConnectionStatus.connected:
      // Normal operation
      break;
    case ConnectionStatus.reconnecting:
      // Automatic reconnection in progress
      break;
    case ConnectionStatus.error:
      // Handle connection errors
      break;
    case ConnectionStatus.disconnected:
      // Clean disconnection
      break;
  }
});
```

## Examples

Check the `example/` directory for complete working examples:

- `main_server.dart`: Complete server implementation
- `main_client.dart`: Interactive client demo

## Contributing

Contributions are welcome! Please read the contributing guidelines and submit pull requests to the main repository.

## Related Packages

- [crdt_lf](https://pub.dev/packages/crdt_lf): The underlying CRDT implementation
- [web_socket_channel](https://pub.dev/packages/web_socket_channel): WebSocket communication layer
- [hlc_dart](https://pub.dev/packages/hlc_dart)

