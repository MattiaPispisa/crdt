import 'package:crdt_lf/crdt_lf.dart';

import '../common/prepared_cycle_benchmark.dart';

/// One remote delete applied with `applyChange`, on a document that holds
/// [containers] open containers and [deleted] ids deleted before.
///
/// The deleted id is open nowhere, so the cycle measures what the document
/// does around a delete, not the close of a handler.
class RemoteDeleteBenchmark extends PreparedCycleBenchmark {
  /// Creates the benchmark reported under `name`.
  RemoteDeleteBenchmark(
    super.name, {
    required this.containers,
    required this.deleted,
  });

  /// How many open containers the target holds, each with one child.
  final int containers;

  /// How many ids the target has deleted before the timed cycles.
  final int deleted;

  static final _type = CRDTFugueTextHandler.spec.type;

  late CRDTDocument _source;
  late CRDTDocument _target;
  late Change _pending;

  @override
  void setup() {
    _source = CRDTDocument();
    _source.runInTransaction(() {
      _source.deleteHandlerRef(HandlerRef('first', _type));
      for (var i = 0; i < deleted; i++) {
        _source.deleteHandlerRef(HandlerRef('old$i', _type));
      }
    });

    _target = CRDTDocument();
    _target.runInTransaction(() {
      for (var i = 0; i < containers; i++) {
        CRDTMapRefHandler(_target, 'c$i')
            .child('child', CRDTFugueTextHandler.spec);
      }
    });
    // The first delete after the containers opened reads all of them once.
    _target.importChanges(_source.exportChanges());
  }

  @override
  void prepare(int round) {
    final before = _source.version;
    _source.deleteHandlerRef(HandlerRef('v$round', _type));
    _pending = _source.exportChanges(from: before).single;
  }

  @override
  void cycle(int round) {
    _target.applyChange(_pending);
    if (!_target.isDeleted('v$round')) {
      throw StateError('delete lost');
    }
  }
}

void main() {
  for (final count in [100, 1000, 10000]) {
    RemoteDeleteBenchmark(
      'Remote delete with $count open containers',
      containers: count,
      deleted: 0,
    ).report();
  }
  for (final count in [100, 1000, 10000]) {
    RemoteDeleteBenchmark(
      'Remote delete after $count deletes',
      containers: 10,
      deleted: count,
    ).report();
  }
}
