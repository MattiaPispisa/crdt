import 'package:crdt_lf/crdt_lf.dart';

import 'mock_operation.dart';

/// Test handler for testing purposes
class MockHandler extends Handler<String> {
  MockHandler(super.doc);

  @override
  String get id => 'test-handler';

  @override
  String getSnapshotState() => 'test_state';

  @override
  OperationFactory get operationFactory => (payload) => MockOperation(this);
}
