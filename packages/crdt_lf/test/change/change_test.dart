import 'package:crdt_lf/src/document.dart';
import 'package:test/test.dart';
import 'package:crdt_lf/src/change/change.dart';
import 'package:crdt_lf/src/operation/id.dart';
import 'package:crdt_lf/src/peer_id.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'package:crdt_lf/src/operation/operation.dart';
import 'package:crdt_lf/src/operation/type.dart';
import 'package:crdt_lf/src/handler/handler.dart';

class TestHandler extends Handler {
  TestHandler(CRDTDocument doc) : super(doc);

  @override
  String get id => 'test-handler';

  @override
  String getState() {
    return '';
  }
}

class TestOperation extends Operation {
  const TestOperation({
    required super.id,
    required super.type,
  });

  factory TestOperation.fromHandler(Handler handler) {
    return TestOperation(
      id: handler.id,
      type: OperationType.insert(handler),
    );
  }

  @override
  dynamic toPayload() => id;
}

void main() {
  group('Change', () {
    late OperationId id;
    late Set<OperationId> deps;
    late HybridLogicalClock hlc;
    late PeerId author;
    late Operation operation;
    late Handler handler;

    setUp(() {
      final doc = CRDTDocument();
      handler = TestHandler(doc);
      deps = {OperationId.parse('3a5cd393-813c-46c8-97f3-9e99a6f2c8be@1.1')};
      hlc = HybridLogicalClock(l: 1, c: 2);
      author = PeerId.generate();
      operation = TestOperation.fromHandler(handler);
      id = OperationId(author, hlc);
    });

    test('creates a new change with valid parameters', () {
      final change = Change(
        id: id,
        operation: operation,
        deps: deps,
        hlc: hlc,
        author: author,
      );

      expect(change.id, equals(id));
      expect(change.deps, equals(deps));
      expect(change.hlc, equals(hlc));
      expect(change.author, equals(author));
      expect(change.payload, equals(operation.toPayload()));
    });

    test('serializes and deserializes correctly', () {
      final change = Change(
        id: id,
        operation: operation,
        deps: deps,
        hlc: hlc,
        author: author,
      );

      final json = change.toJson();
      final deserialized = Change.fromJson(json);

      expect(deserialized, equals(change));
    });

    test('compares equal changes correctly', () {
      final change1 = Change(
        id: id,
        operation: operation,
        deps: deps,
        hlc: hlc,
        author: author,
      );

      final change2 = Change(
        id: id,
        operation: operation,
        deps: deps,
        hlc: hlc,
        author: author,
      );

      expect(change1, equals(change2));
    });

    test('compares different changes correctly', () {
      final change1 = Change(
        id: id,
        operation: operation,
        deps: deps,
        hlc: hlc,
        author: author,
      );

      final change2 = Change(
        id: OperationId.parse('b7353649-1b52-43b0-9dbc-a843e3308cb0@1.3'),
        operation: operation,
        deps: deps,
        hlc: hlc,
        author: author,
      );

      expect(change1, isNot(equals(change2)));
    });

    test('sorts changes by HLC correctly', () {
      final change1 = Change(
        id: OperationId.parse('2951e709-9576-4e1d-9ec8-52e557bfa8cd@1.1'),
        operation: operation,
        deps: deps,
        hlc: HybridLogicalClock(l: 1, c: 1),
        author: author,
      );

      final change2 = Change(
        id: OperationId.parse('112e1539-c71a-4217-9100-4554f79096e4@1.2'),
        operation: operation,
        deps: deps,
        hlc: HybridLogicalClock(l: 2, c: 1),
        author: author,
      );

      final changes = [change2, change1];
      final sorted = changes.sorted();

      expect(sorted[0], equals(change1));
      expect(sorted[1], equals(change2));
    });

    test('toString returns correct format', () {
      final change = Change(
        id: id,
        operation: operation,
        deps: deps,
        hlc: hlc,
        author: author,
      );

      final expected =
          'Change(id: $id, deps: [${deps.first}], hlc: $hlc, author: $author, payload: ${operation.toPayload()})';
      expect(change.toString(), equals(expected));
    });

    test('hashCode is consistent with equality', () {
      final change1 = Change(
        id: id,
        operation: operation,
        deps: deps,
        hlc: hlc,
        author: author,
      );

      final change2 = Change(
        id: id,
        operation: operation,
        deps: deps,
        hlc: hlc,
        author: author,
      );

      final change3 = Change(
        id: OperationId.parse('b7353649-1b52-43b0-9dbc-a843e3308cb0@1.3'),
        operation: operation,
        deps: deps,
        hlc: hlc,
        author: author,
      );

      expect(change1.hashCode, equals(change2.hashCode));
      expect(change1.hashCode, isNot(equals(change3.hashCode)));
    });

    test('hashCode handles different dependencies correctly', () {
      final deps1 = {
        OperationId.parse('3a5cd393-813c-46c8-97f3-9e99a6f2c8be@1.1')
      };
      final deps2 = {
        OperationId.parse('b7353649-1b52-43b0-9dbc-a843e3308cb0@1.3')
      };

      final change1 = Change(
        id: id,
        operation: operation,
        deps: deps1,
        hlc: hlc,
        author: author,
      );

      final change2 = Change(
        id: id,
        operation: operation,
        deps: deps2,
        hlc: hlc,
        author: author,
      );

      expect(change1.hashCode, isNot(equals(change2.hashCode)));
    });
  });
}
