import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:crdt_lf/crdt_lf.dart';

import 'custom_emitter.dart';

const _kOperationsCount = 1000;

/// An operation to apply to a handler during a benchmark run.
typedef HandlerOperation<T> = void Function(T handler);

/// Benchmark for handler
/// Performs operations on a fresh document and gets the value of the
/// handler after all operations are performed.
///
/// A fresh document is created on every [run] so that state does not
/// accumulate across benchmark iterations and the reported time measures
/// a reproducible amount of work.
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

  final T Function(CRDTDocument document) _handlerFactory;
  late final List<HandlerOperation<T>> _operations;

  final bool _useIncrementalCacheUpdate;
  final int _operationsCount;

  @override
  void setup() {
    // Generate a list of operations to perform
    _operations = generateOperations(_operationsCount);
  }

  /// Gets the value of the handler
  dynamic getHandlerValue(T handler);

  @override
  void run() {
    final document = CRDTDocument(peerId: PeerId.generate());
    final handler = _handlerFactory(document)
      ..useIncrementalCacheUpdate = _useIncrementalCacheUpdate;

    if (_useIncrementalCacheUpdate) {
      // Warm the cache so operations update it incrementally
      getHandlerValue(handler);
    }

    for (final operation in _operations) {
      operation(handler);
    }
    getHandlerValue(handler);
  }

  /// Generates a list of operations for benchmarking
  List<HandlerOperation<T>> generateOperations(int count);
}
