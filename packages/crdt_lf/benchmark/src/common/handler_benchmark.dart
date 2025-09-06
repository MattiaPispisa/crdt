import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:crdt_lf/crdt_lf.dart';

import 'custom_emitter.dart';

const _kOperationsCount = 1000;

typedef VoidCallback = void Function();

/// Benchmark for handler
/// Performs operations and get the value of the handler
/// after all operations are performed
abstract class BaseHandlerOperationsBenchmark<T extends Handler<dynamic>>
    extends BenchmarkBase {
  /// Creates a new base handler operations benchmark
  ///
  /// [handlerFactory] is a function that creates a new handler
  /// [useIncrementalCacheUpdate] is a boolean that indicates
  /// if the incremental cache update is enabled
  /// [operationsCount] is the number of operations to perform, default is 1000
  BaseHandlerOperationsBenchmark({
    required String handlerName,
    required T Function(CRDTDocument) handlerFactory,
    required bool useIncrementalCacheUpdate,
    int operationsCount = _kOperationsCount,
  })  : _operationsCount = operationsCount,
        _handlerFactory = handlerFactory,
        _useIncrementalCacheUpdate = useIncrementalCacheUpdate,
        super(
          '$handlerName do $operationsCount operations and get value'
          ' (incremental cache update: $useIncrementalCacheUpdate)',
          emitter: const CustomEmitter(),
        );

  late final CRDTDocument _document;
  final T Function(CRDTDocument document) _handlerFactory;
  late final List<VoidCallback> _operations;
  late final T _handler;

  final bool _useIncrementalCacheUpdate;
  final int _operationsCount;

  @override
  void setup() {
    _document = CRDTDocument(peerId: PeerId.generate());
    _handler = _handlerFactory(_document);
    // Generate a list of operations to perform
    _operations = generateOperations(_handler, _operationsCount);
  }

  /// Gets the value of the handler
  dynamic getHandlerValue(T handler);

  @override
  void run() {
    if (_useIncrementalCacheUpdate) {
      _handler.useIncrementalCacheUpdate = true;
      getHandlerValue(_handler);
    } else {
      _handler.useIncrementalCacheUpdate = false;
    }
    for (final operation in _operations) {
      operation();
    }
    getHandlerValue(_handler);
  }

  /// Generates a list of operations for benchmarking
  List<VoidCallback> generateOperations(T handler, int count);
}
