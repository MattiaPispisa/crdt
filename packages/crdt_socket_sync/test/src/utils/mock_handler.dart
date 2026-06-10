import 'dart:convert';
import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';

import 'mock_operation.dart';

/// Test handler for testing purposes
class MockHandler extends Handler<String> {
  MockHandler(super.doc);

  @override
  String get id => 'test-handler';

  @override
  Uint8List getSnapshotState() =>
      Uint8List.fromList(utf8.encode('test_state'));

  @override
  OperationFactory get operationFactory => (payload) => MockOperation(this);
}
