import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';

/// A test handler for CRDT operations
class TestHandler extends Handler<dynamic> {
  /// Create a new test handler
  TestHandler(
    super.doc, {
    this.id = 'test-handler',
  });

  @override
  final String id;

  @override
  Uint8List getSnapshotState() {
    return Uint8List(0);
  }

  @override
  OperationFactory get operationFactory => (operationBytes) {
        final env = OperationEnvelopeCodec.decode(operationBytes);
        if (env.handlerId != id) {
          return null;
        }
        return TestOperation.fromHandler(this);
      };
}

/// A test operation for CRDT operations
class TestOperation extends Operation {
  /// Create a new test operation
  const TestOperation({
    required super.id,
    required super.type,
  });

  /// Create a new test operation from a handler
  factory TestOperation.fromHandler(Handler<dynamic> handler) {
    return TestOperation(
      id: handler.id,
      type: OperationType.insert(handler),
    );
  }

  @override
  Uint8List toBodyBytes() {
    return Uint8List(0);
  }
}
