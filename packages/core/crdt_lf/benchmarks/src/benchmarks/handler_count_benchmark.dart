import 'package:crdt_lf/crdt_lf.dart';

import '../common/prepared_cycle_benchmark.dart';

const _kind = 'bench.register';

/// One edit on a document that holds [handlerCount] warm handlers.
///
/// The edit touches one handler. What it costs should not depend on how many
/// other handlers the document holds: that is what a document with thousands
/// of aggregates needs.
abstract class HandlerCountBenchmark extends PreparedCycleBenchmark {
  /// Creates the benchmark reported under `name`.
  HandlerCountBenchmark(super.name, this.handlerCount);

  /// How many handlers the measured document holds.
  final int handlerCount;

  /// The document whose cost is measured.
  late CRDTDocument target;

  /// The handlers of [target], every one with a value read once.
  late List<CRDTRegisterHandler<int>> targetHandlers;

  /// Builds [target] and fills [targetHandlers].
  void buildTarget({Iterable<Change> imported = const []}) {
    target = CRDTDocument();
    targetHandlers = [
      for (var i = 0; i < handlerCount; i++)
        CRDTRegisterHandler<int>(target, 'h$i', handlerType: _kind),
    ];
    target.importChanges(imported.toList());
    target.runInTransaction(() {
      for (final handler in targetHandlers) {
        if (handler.value == null) {
          handler.set(0);
        }
      }
    });
    for (final handler in targetHandlers) {
      handler.value;
    }
  }
}

/// A local write on one handler, then a read of it.
class LocalWriteHandlerCountBenchmark extends HandlerCountBenchmark {
  /// Creates the benchmark for [handlerCount] handlers.
  LocalWriteHandlerCountBenchmark(int handlerCount)
      : super('Local write + read with $handlerCount handlers', handlerCount);

  @override
  void setup() => buildTarget();

  @override
  void cycle(int round) {
    final handler = targetHandlers[round % 16]..set(round);
    if (handler.value != round) {
      throw StateError('write lost');
    }
  }
}

/// One remote change applied with `applyChange`, then a read of its handler.
class RemoteApplyHandlerCountBenchmark extends HandlerCountBenchmark {
  /// Creates the benchmark for [handlerCount] handlers.
  RemoteApplyHandlerCountBenchmark(int handlerCount)
      : super('Remote applyChange + read with $handlerCount handlers',
            handlerCount);

  late CRDTDocument _source;
  late CRDTRegisterHandler<int> _sourceHandler;
  late Change _pending;

  @override
  void setup() {
    _source = CRDTDocument();
    _sourceHandler = CRDTRegisterHandler<int>(_source, 'h0', handlerType: _kind)
      ..set(0);
    buildTarget(imported: _source.exportChanges());
  }

  @override
  void prepare(int round) {
    final before = _source.version;
    _sourceHandler.set(round);
    _pending = _source.exportChanges(from: before).single;
  }

  @override
  void cycle(int round) {
    target.applyChange(_pending);
    if (targetHandlers.first.value != round) {
      throw StateError('change lost');
    }
  }
}

/// A batch of 100 remote changes, one per handler, applied with
/// `importChanges`, then a read of one of them.
class ImportBatchHandlerCountBenchmark extends HandlerCountBenchmark {
  /// Creates the benchmark for [handlerCount] handlers.
  ImportBatchHandlerCountBenchmark(int handlerCount)
      : super('importChanges of 100 changes with $handlerCount handlers',
            handlerCount);

  static const _batchSize = 100;

  late CRDTDocument _source;
  late List<CRDTRegisterHandler<int>> _sourceHandlers;
  late List<Change> _pending;

  @override
  void setup() {
    _source = CRDTDocument();
    _sourceHandlers = [
      for (var i = 0; i < _batchSize; i++)
        CRDTRegisterHandler<int>(_source, 'h$i', handlerType: _kind),
    ];
    _source.runInTransaction(() {
      for (final handler in _sourceHandlers) {
        handler.set(0);
      }
    });
    buildTarget(imported: _source.exportChanges());
  }

  @override
  void prepare(int round) {
    final before = _source.version;
    _source.runInTransaction(() {
      for (final handler in _sourceHandlers) {
        handler.set(round);
      }
    });
    _pending = _source.exportChanges(from: before);
  }

  @override
  void cycle(int round) {
    target.importChanges(_pending);
    if (targetHandlers.first.value != round) {
      throw StateError('batch lost');
    }
  }
}

void main() {
  for (final count in [100, 1000, 10000]) {
    LocalWriteHandlerCountBenchmark(count).report();
  }
  for (final count in [100, 1000, 10000]) {
    RemoteApplyHandlerCountBenchmark(count).report();
  }
  for (final count in [100, 1000, 10000]) {
    ImportBatchHandlerCountBenchmark(count).report();
  }
}
