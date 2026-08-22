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
/// reading real isolate heap usage aren't available through `dart:io`, so
/// the process running this benchmark must be launched with
/// `--enable-vm-service`.
///
/// [report] opens its own VM service connection and closes it before
/// returning, rather than keeping one open for the process's lifetime: an
/// open connection is a live socket listener, which would stop the process
/// from exiting once every benchmark in a file has run.
abstract class MemoryBenchmarkBase {
  /// Creates a benchmark reported under [name].
  MemoryBenchmarkBase(this.name, {this.emitter = const PrintMemoryEmitter()});

  /// This benchmark's name, as shown in the emitted result.
  final String name;

  /// Where the measured byte delta is reported.
  final MemoryEmitter emitter;

  /// Builds fixtures. Excluded from the measured byte delta.
  void setup() {}

  /// The operation whose heap cost is measured.
  void run();

  /// Releases fixtures. Excluded from the measured byte delta.
  void teardown() {}

  /// Runs [setup], measures the heap delta caused by [run], then [teardown],
  /// and reports the byte delta via [emitter].
  Future<void> report() async {
    final service = await _connect();
    try {
      final isolateId =
          developer.Service.getIsolateId(isolate.Isolate.current)!;

      setup();
      final before = await _heapUsageBytes(service, isolateId);
      run();
      final after = await _heapUsageBytes(service, isolateId);
      teardown();

      emitter.emit(name, after - before);
    } finally {
      await service.dispose();
    }
  }

  static Future<VmService> _connect() async {
    final info = await developer.Service.getInfo();
    final uri = info.serverUri;
    if (uri == null) {
      throw StateError(
        'No VM service URI found. Memory benchmarks must run with '
        '--enable-vm-service.',
      );
    }
    final wsUri = uri.replace(scheme: 'ws', path: '${uri.path}ws');
    return vmServiceConnectUri(wsUri.toString());
  }

  static Future<int> _heapUsageBytes(
    VmService service,
    String isolateId,
  ) async {
    await service.getAllocationProfile(isolateId, gc: true);
    final usage = await service.getMemoryUsage(isolateId);
    return usage.heapUsage!;
  }
}
