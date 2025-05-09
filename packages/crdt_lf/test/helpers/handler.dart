import 'package:crdt_lf/crdt_lf.dart';

/// A test handler for CRDT operations
class TestHandler extends Handler<dynamic> {
  /// Create a new test handler
  TestHandler(super.doc);

  @override
  String get id => 'test-handler';

  @override
  String getSnapshotState() {
    return '';
  }
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

  /// Return the payload of the operation
  @override
  Map<String, dynamic> toPayload() => {'id': id};
}
