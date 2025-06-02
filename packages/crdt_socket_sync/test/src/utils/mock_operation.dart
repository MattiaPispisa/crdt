import 'package:crdt_lf/crdt_lf.dart';

/// Test operation for testing purposes
class MockOperation extends Operation {
  MockOperation(Handler<dynamic> handler)
      : super(
          id: handler.id,
          type: OperationType.insert(handler),
        );

  @override
  Map<String, dynamic> toPayload() => {
        'type': type.toPayload(),
        'id': id,
        'test': true,
      };
}
