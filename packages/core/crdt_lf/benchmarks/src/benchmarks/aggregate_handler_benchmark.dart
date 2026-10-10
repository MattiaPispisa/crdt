import 'dart:convert';
import 'dart:typed_data';

import 'package:benchmark_infrastructure/benchmark_infrastructure.dart';
import 'package:crdt_lf/crdt_lf.dart';

/// How many events have been folded, and the last one: a reducer that costs
/// next to nothing, so the score is the handler's own work.
class _Tally {
  const _Tally(this.count, this.last);

  final int count;
  final String last;
}

class _TallyAggregate extends AggregateDefinition<_Tally, String> {
  const _TallyAggregate();

  @override
  String get handlerType => 'bench.tally';

  @override
  _Tally initial() => const _Tally(0, '');

  @override
  _Tally reduce(_Tally state, String event, EventContext context) =>
      _Tally(state.count + 1, event);

  @override
  ValueCodec<String> get eventCodec => const _Utf8Codec();

  @override
  ValueCodec<_Tally> get stateCodec => const _TallyCodec();
}

class _Utf8Codec implements ValueCodec<String> {
  const _Utf8Codec();

  @override
  Uint8List encode(String value) => utf8.encode(value);

  @override
  String decode(Uint8List bytes) => utf8.decode(bytes);
}

class _TallyCodec implements ValueCodec<_Tally> {
  const _TallyCodec();

  @override
  Uint8List encode(_Tally value) {
    final out = BytesBuilder(copy: false);
    UVarint.write(value.count, out);
    UVarint.writeString(value.last, out);
    return out.toBytes();
  }

  @override
  _Tally decode(Uint8List bytes) {
    final count = UVarint.read(bytes, offset: 0);
    final last =
        UVarint.readString(bytes, offset: count.nextOffset, what: 'last');
    return _Tally(count.value, last.value);
  }
}

CRDTAggregateHandler<_Tally, String> _tally(CRDTDocument doc) =>
    CRDTAggregateHandler<_Tally, String>(
      doc,
      'tally',
      definition: const _TallyAggregate(),
    );

/// A local dispatch of one event, then a read.
class AggregateDispatchBenchmark extends FixedCycleTimedBenchmark {
  /// Creates the benchmark.
  AggregateDispatchBenchmark() : super('Aggregate dispatch + read');

  late CRDTAggregateHandler<_Tally, String> _handler;
  var _round = 0;

  @override
  void setup() {
    _handler = _tally(CRDTDocument())..value;
  }

  @override
  void run() {
    _handler.dispatch('event ${_round++}');
    if (_handler.value.count == 0) {
      throw StateError('event lost');
    }
  }
}

/// A read with nothing cached: the whole history replayed.
class AggregateReplayBenchmark extends TimedBenchmarkBase {
  /// Creates the benchmark for [events] events in [events] changes.
  AggregateReplayBenchmark(this.events)
      : super('Aggregate replay of $events events');

  /// How many events the history holds.
  final int events;

  late CRDTAggregateHandler<_Tally, String> _handler;

  @override
  void setup() {
    _handler = _tally(CRDTDocument());
    for (var i = 0; i < events; i++) {
      _handler.dispatch('event $i');
    }
  }

  @override
  void run() {
    _handler.invalidateCache();
    if (_handler.value.count != events) {
      throw StateError('replay lost events');
    }
  }
}

/// A remote event applied, then a read, on a history of [events] events.
///
/// From the past, the change sorts before what the target already folded, so
/// the target replays its history instead of folding one event.
class AggregateRemoteBenchmark extends TimedBenchmarkBase {
  /// Creates the benchmark.
  AggregateRemoteBenchmark(this.events, {required this.fromThePast})
      : super(
          'Aggregate remote event + read on $events events'
          '${fromThePast ? ' (from the past)' : ''}',
          runsPerMeasure: 1,
        );

  /// How many events the history holds.
  final int events;

  /// Whether the remote change sorts before the target's newest one.
  final bool fromThePast;

  static const _warmup = Duration(milliseconds: 400);
  static const _measuredCycles = 100;
  static const _batches = 5;

  late CRDTDocument _source;
  late CRDTAggregateHandler<_Tally, String> _sourceHandler;
  late CRDTDocument _target;
  late CRDTAggregateHandler<_Tally, String> _targetHandler;
  late Change _pending;

  @override
  void setup() {
    _source = CRDTDocument();
    _sourceHandler = _tally(_source);
    for (var i = 0; i < events; i++) {
      _sourceHandler.dispatch('event $i');
    }
    _target = CRDTDocument()..importChanges(_source.exportChanges());
    _targetHandler = _tally(_target)..value;
  }

  void _prepare(int round) {
    final before = _source.version;
    _sourceHandler.dispatch('remote $round');
    _pending = _source.exportChanges(from: before).single;
    if (fromThePast) {
      // The target writes after the source, so the change sorts before it.
      _target.prepareMutation();
      _targetHandler
        ..dispatch('local $round')
        ..value;
    }
  }

  @override
  double measure() {
    setup();
    var round = 0;
    final warmup = Stopwatch()..start();
    while (warmup.elapsed < _warmup) {
      _prepare(round);
      _cycle();
      round++;
    }

    var best = double.infinity;
    for (var batch = 0; batch < _batches; batch++) {
      setup();
      final stopwatch = Stopwatch();
      for (var i = 0; i < _measuredCycles; i++) {
        _prepare(round);
        stopwatch.start();
        _cycle();
        stopwatch.stop();
        round++;
      }
      final perCycle = stopwatch.elapsedMicroseconds / _measuredCycles;
      if (perCycle < best) {
        best = perCycle;
      }
    }
    teardown();
    return best;
  }

  void _cycle() {
    _target.applyChange(_pending);
    if (_targetHandler.value.count == 0) {
      throw StateError('change lost');
    }
  }
}

void main() {
  AggregateDispatchBenchmark().report();
  AggregateReplayBenchmark(1000).report();
  AggregateRemoteBenchmark(1000, fromThePast: false).report();
  AggregateRemoteBenchmark(1000, fromThePast: true).report();
}
