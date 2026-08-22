import 'dart:developer' as developer;
import 'dart:isolate' as isolate;

import 'package:benchmark_infrastructure/src/memory/memory_emitter.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

/// A benchmark that measures the heap footprint of [run], not its speed.
///
/// Mirrors `TimedBenchmarkBase`'s `setup()` / `run()` / `teardown()` shape:
/// [setup] builds fixtures that are excluded from the measurement, [run] is
/// the operation whose heap cost is measured, and [teardown] cleans up
/// after. Measuring needs the Dart VM service, because forcing a GC and
/// reading real isolate heap usage aren't available through `dart:io`
///
/// [run] returns the object graph to measure. That return value is the whole
/// point of this class: the measurement forces a GC, so anything [run] only
/// held in a local is already collectable garbage by the time the heap is
/// read. Returning it parks it in a GC root until after the reading.
///
/// [report] opens its own VM service connection and closes it before
/// returning, rather than keeping one open for the process's lifetime: an
/// open connection is a live socket listener, which would stop the process
/// from exiting once every benchmark in a file has run.
abstract class MemoryBenchmarkBase {
  /// Creates a benchmark reported under [name].
  ///
  /// [run] is called [warmupRuns] times before measuring, then [samples]
  /// times under measurement, and the median of those deltas is reported.
  /// The warm-up keeps first-touch cost (JIT'd code, lazy statics) out of
  /// the number.
  ///
  /// The median, not the minimum: a forced GC does not always reclaim
  /// everything, and leftover garbage pulls a sample in either direction —
  /// up when it lands in the reading after [run], down when it inflates the
  /// reading before it. The median drops both kinds of outlier; the minimum
  /// would keep the worst of the second kind.
  ///
  /// Both defaults assume [run] is repeatable, the same way the timed
  /// harness loops its `run()`. A benchmark that mutates a fixture built in
  /// [setup] must pass `warmupRuns: 0, samples: 1`.
  MemoryBenchmarkBase(
    this.name, {
    this.emitter = const PrintMemoryEmitter(),
    this.warmupRuns = 1,
    this.samples = 5,
  })  : assert(warmupRuns >= 0, 'warmupRuns cannot be negative'),
        assert(samples >= 1, 'at least one sample is needed');

  /// Holds the value returned by [run] across the measurement.
  ///
  /// Static on purpose: a static field is an unconditional GC root, so
  /// keeping the graph alive does not depend on the async state machine of
  /// [report] holding on to `this`.
  ///
  // Never read on purpose: the write is the whole job. Reading it back
  // would let the compiler see the value as needed for something, which is
  // not the point — the point is that the GC can see it.
  // ignore: unused_field
  static Object? _anchor;

  /// This benchmark's name, as shown in the emitted result.
  final String name;

  /// Where the measured byte delta is reported.
  final MemoryEmitter emitter;

  /// How many times [run] is called before measuring starts.
  final int warmupRuns;

  /// How many measured [run] calls the reported median is taken from.
  final int samples;

  /// Builds fixtures. Excluded from the measured byte delta.
  void setup() {}

  /// The operation whose heap cost is measured.
  ///
  /// Returns the object graph to measure. The returned value stays
  /// reachable until after the heap is read, so its bytes are counted. A
  /// benchmark that returns `null` measures leftover garbage instead of
  /// retained size.
  Object? run();

  /// Releases fixtures. Excluded from the measured byte delta.
  void teardown() {}

  /// Runs [setup], measures the heap delta caused by [run], then [teardown],
  /// and reports the median byte delta via [emitter].
  Future<void> report() async {
    final service = await _connect();
    try {
      final isolateId =
          developer.Service.getIsolateId(isolate.Isolate.current)!;

      setup();
      try {
        for (var i = 0; i < warmupRuns; i++) {
          _anchor = run();
          _anchor = null;
        }

        final deltas = <int>[];
        for (var i = 0; i < samples; i++) {
          final before = await _heapUsageBytes(service, isolateId);
          _anchor = run();
          final after = await _heapUsageBytes(service, isolateId);
          _anchor = null;

          deltas.add(after - before);
        }

        emitter.emit(name, _median(deltas));
      } finally {
        teardown();
      }
    } finally {
      await service.dispose();
    }
  }

  /// The middle value of [values], or the lower of the two middle ones when
  /// the count is even.
  static int _median(List<int> values) {
    final sorted = [...values]..sort();
    return sorted[(sorted.length - 1) ~/ 2];
  }

  static Future<VmService> _connect() async {
    final uri = (await developer.Service.getInfo()).serverUri ??
        (await developer.Service.controlWebServer(
          enable: true,
          silenceOutput: true,
        ))
            .serverUri;
    if (uri == null) {
      throw StateError(
        'No VM service URI found. Memory benchmarks need a VM with the '
        'service available.',
      );
    }
    final wsUri = uri.replace(scheme: 'ws', path: '${uri.path}ws');
    return vmServiceConnectUri(wsUri.toString());
  }

  static Future<int> _heapUsageBytes(
    VmService service,
    String isolateId,
  ) async {
    // Twice: the first cycle can leave behind objects that only become
    // unreachable once it has run, e.g. anything held by a finalizer.
    await service.getAllocationProfile(isolateId, gc: true);
    await service.getAllocationProfile(isolateId, gc: true);
    final usage = await service.getMemoryUsage(isolateId);
    return usage.heapUsage!;
  }
}
