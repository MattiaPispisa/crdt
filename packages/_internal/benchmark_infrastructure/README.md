# benchmark_infrastructure

Private, unpublished package (`publish_to: none`) holding the shared
benchmark-running infrastructure reused by every package's `benchmarks/`
folder in this monorepo.

## The `benchmarks/` convention

Any package can opt into `melos run benchmark` by adding a `benchmarks/`
folder (plural — this is what `melos.yaml`'s `benchmark` script filters on)
laid out like this:

```
benchmarks/
  src/
    timed/
      *_benchmark.dart   # one file per group of related timed benchmarks
    memory/
      *_benchmark.dart   # one file per group of related memory benchmarks
    common/
      # package-local base classes, if any (e.g. crdt_lf's
      # BaseHandlerOperationsBenchmark, which builds on TimedBenchmarkBase)
  results.md               # generated, committed as a baseline (timed)
  memory_results.md         # generated, committed as a baseline (memory)
```

A package can have either subfolder, or both — each is discovered and run
independently.

### Timed benchmarks

Each `*_benchmark.dart` file under `src/timed/` extends `TimedBenchmarkBase`
(from this package) instead of `benchmark_harness`'s `BenchmarkBase`
directly, and its `main()` calls `.report()` on each benchmark class,
exactly as with plain `benchmark_harness`. `TimedBenchmarkBase` wires up the
emitter, so a benchmark only needs to name itself:

```dart
import 'package:benchmark_infrastructure/benchmark_infrastructure.dart';

class MyBenchmark extends TimedBenchmarkBase {
  MyBenchmark() : super('My benchmark name');

  @override
  void run() { ... }
}

void main() {
  MyBenchmark().report();
}
```

### Memory benchmarks

Each `*_benchmark.dart` file under `src/memory/` extends
`MemoryBenchmarkBase` instead. It has the same `setup()` / `run()` /
`teardown()` shape as `TimedBenchmarkBase`, but measures the heap bytes
`run()` allocates instead of how long it takes — `setup()`'s allocations
(fixtures) aren't counted. `report()` is `async`, because measuring needs a
round trip to the Dart VM service:

```dart
import 'package:benchmark_infrastructure/benchmark_infrastructure.dart';

class MyMemoryBenchmark extends MemoryBenchmarkBase {
  MyMemoryBenchmark() : super('My memory benchmark name');

  @override
  void run() { ... }
}

Future<void> main() async {
  await MyMemoryBenchmark().report();
}
```

Memory benchmark files can't be run directly with `dart run` the way timed
ones can — `MemoryBenchmarkBase` needs the VM service, which only exists
when the process is launched with `--enable-vm-service` (the memory runner
does this for you; see below).

Add this package as a `dev_dependency` with a `path:` reference (it's
dev-only tooling, like `test`, not shipped `lib/` code):

```yaml
dev_dependencies:
  benchmark_infrastructure:
    path: ../../_internal/benchmark_infrastructure
```

## Running

`melos run benchmark` runs every package with a `benchmarks/` folder. From
inside one such package, `dart run benchmark_infrastructure:run_benchmarks`
does the same for just that package: it discovers every
`benchmarks/src/timed/*_benchmark.dart` file and every
`benchmarks/src/memory/*_benchmark.dart` file, runs each as its own
subprocess (a fresh VM per file), and writes the aggregated results as
Markdown tables to `benchmarks/results.md` and `benchmarks/memory_results.md`
respectively. A package missing one of the two subfolders just gets a note
on stderr for that half — the other still runs.

Each runner talks to its subprocesses over stdout: the timed `CustomEmitter`
prints one line per result tagged with the `benchmarkResultMarker` prefix
(`{"name": ..., "microseconds": ...}`); the memory `PrintMemoryEmitter` does
the same with the `memoryResultMarker` prefix (`{"name": ..., "bytes":
...}`). Each `tryParse` only looks for its own prefix — no format-specific
parsing to keep in sync on either side, and any other line (progress output,
a stray print, the VM service's own startup banner) is left for the caller
to report instead of being force-fit into a pattern.

Memory subprocesses are launched with `dart run --enable-vm-service=0
--no-pause-isolates-on-exit`: port `0` picks an unused port so back-to-back
runs never collide, and `--no-pause-isolates-on-exit` stops the isolate from
pausing for a debugger on exit, so the subprocess still terminates on its
own once `main()` returns.

## Structure

`lib/src/timed/` is timing-specific: `CustomEmitter`, `TimedBenchmarkBase`,
`BenchmarkResult`, its Markdown renderer, and its runner.
`lib/src/memory/` mirrors it for RAM usage: `PrintMemoryEmitter`,
`MemoryBenchmarkBase`, `MemoryBenchmarkResult`, its own Markdown renderer,
and its own runner. Neither reshapes the other.
