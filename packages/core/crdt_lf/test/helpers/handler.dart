import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';

/// A test handler for CRDT operations
final class TestHandler extends Handler<dynamic> {
  /// Create a new test handler
  TestHandler(
    super.doc, {
    this.id = 'test-handler',
    String handlerType = 'TestHandler',
  }) : spec = HandlerSpec(
          handlerType,
          (doc, id) => TestHandler(doc, id: id, handlerType: handlerType),
          formats: const HandlerFormats(
            operationKinds: {OperationType.kindInsert},
            blobVersions: BlobVersionRange.single(1),
          ),
        );

  @override
  final String id;

  @override
  final HandlerSpec<TestHandler> spec;

  @override
  Uint8List getSnapshotState() {
    return Uint8List(0);
  }

  @override
  late final OperationDecoders operationDecoders = {
    OperationType.kindInsert: (body) => TestOperation.fromHandler(this),
  };
}

/// A test operation for CRDT operations
class TestOperation extends Operation {
  /// Create a new test operation
  TestOperation({
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
