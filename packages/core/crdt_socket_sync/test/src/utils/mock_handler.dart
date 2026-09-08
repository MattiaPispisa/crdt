import 'dart:convert';
import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';

import 'mock_operation.dart';

/// Test handler for testing purposes
final class MockHandler extends Handler<String> {
  MockHandler(super.doc);

  @override
  String get id => 'test-handler';

  @override
  Uint8List getSnapshotState() => Uint8List.fromList(utf8.encode('test_state'));

  @override
  late final OperationDecoders operationDecoders = {
    OperationType.kindInsert: (body) => MockOperation(this),
  };
}

/// A handler that decodes one kind more than [MockHandler].
///
/// Stands for a newer build: the same handler type on the wire, plus a kind an
/// older peer has never heard of.
final class NewerMockHandler extends Handler<String> {
  NewerMockHandler(super.doc) : super(handlerType: 'MockHandler');

  @override
  String get id => 'test-handler';

  @override
  Uint8List getSnapshotState() => Uint8List.fromList(utf8.encode('test_state'));

  @override
  late final OperationDecoders operationDecoders = {
    OperationType.kindInsert: (body) => MockOperation(this),
    OperationType.kindDelete: (body) => MockOperation(this),
  };
}
