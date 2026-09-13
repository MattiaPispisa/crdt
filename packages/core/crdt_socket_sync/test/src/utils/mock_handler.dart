import 'dart:convert';
import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';

import 'mock_operation.dart';

/// Test handler for testing purposes
final class MockHandler extends Handler<String> {
  MockHandler(super.doc);

  @override
  HandlerSpec<MockHandler> get spec => _spec;

  static final HandlerSpec<MockHandler> _spec = HandlerSpec(
    'MockHandler',
    (doc, id) => MockHandler(doc),
    formats: const HandlerFormats(
      operationKinds: {OperationType.kindInsert},
    ),
  );

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
  NewerMockHandler(super.doc);

  /// The tag [MockHandler] answers with, so both stand for the same kind on the
  /// wire.
  @override
  HandlerSpec<NewerMockHandler> get spec => _spec;

  static final HandlerSpec<NewerMockHandler> _spec = HandlerSpec(
    'MockHandler',
    (doc, id) => NewerMockHandler(doc),
    formats: const HandlerFormats(
      operationKinds: {OperationType.kindInsert, OperationType.kindDelete},
    ),
  );

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
