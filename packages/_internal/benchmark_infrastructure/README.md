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
    benchmarks/
      *_benchmark.dart   # one file per group of related benchmarks
    common/
      # package-local base classes, if any (e.g. crdt_lf's
      # BaseHandlerOperationsBenchmark, which builds on TimedBenchmarkBase)
  results.md              # generated, committed as a baseline
```

Each `*_benchmark.dart` file extends `TimedBenchmarkBase` (from this
package) instead of `benchmark_harness`'s `BenchmarkBase` directly, and its
`main()` calls `.report()` on each benchmark class, exactly as with plain
`benchmark_harness`. `TimedBenchmarkBase` wires up the emitter, so a
benchmark only needs to name itself:

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

## Picking a base class

| base | loop | use it when |
| --- | --- | --- |
| `TimedBenchmarkBase` | the harness default: run for at least 2 s | the default. A cycle that leaves no trace. |
| `AsyncTimedBenchmarkBase` | same, but `run()` can await | the cycle cannot be synchronous (e.g. it ends with `await tester.pump()`). |
| `FixedCycleTimedBenchmark` | fixed cycles, fastest batch wins | a cycle **grows** what it measures. |
| `AsyncFixedCycleTimedBenchmark` | the same fixed-cycle loop, awaited | both of the above at once. |

The fixed-cycle bases exist because the default loop keeps going until two
seconds have passed. They run `batches`
batches of `measuredCycles` cycles each, warm up for `warmupDuration` first,
call `setup()` again before every batch (`setupPerBatch`), and report the
**fastest** batch — a GC pause can only make a batch slower, so the minimum is
the cleanest reading.

After each per-batch `setup()` they run `settleCycles` cycles untimed. A
freshly built document is cold: the first operation on it may build an index
or resolve a projection that every later operation reuses. That cost belongs
to the document, not to the cycle, and spread over a batch it can dominate —
one text row read 253 µs with the cold cycle inside the batch and 60 µs with
it outside.

```dart
class MyGrowingBenchmark extends FixedCycleTimedBenchmark {
  MyGrowingBenchmark() : super('My benchmark name', measuredCycles: 200);

  @override
  void setup() { ... }

  @override
  void run() { ... }
}
```

## Installing

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
`benchmarks/src/benchmarks/*_benchmark.dart` file, runs each as its own
`dart run` subprocess (a fresh VM per file), and writes the aggregated
results as a Markdown table to `benchmarks/results.md`.

The runner talks to each subprocess over stdout: `CustomEmitter` prints one
line per result, tagged with the `benchmarkResultMarker` prefix and a JSON
payload (`{"name": ..., "microseconds": ...}`). `BenchmarkResult.tryParse`
only looks for that prefix — no format-specific parsing to keep in sync on
either side, and any other line (progress output, a stray print) is left for
the caller to report instead of being force-fit into a pattern.

## Structure

Everything under `lib/src/timed/` is timing-specific: `CustomEmitter`,
`TimedBenchmarkBase`, `BenchmarkResult`, the Markdown renderer, and the
runner. A future RAM-usage benchmark feature gets its own `lib/src/memory/`
sibling instead of reshaping this one.
