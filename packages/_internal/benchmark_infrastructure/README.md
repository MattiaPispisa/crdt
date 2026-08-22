# benchmark_infrastructure

Private benchmark-running infrastructure reused by every package's `benchmarks/`
folder in this monorepo.

## The `benchmarks/` convention

Any package can opt into `melos run benchmark` by adding a `benchmarks/`
folder:

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
  timed_results.md          # generated, committed as a baseline (timed)
  memory_results.md         # generated, committed as a baseline (memory)
```

A package can have either subfolder, or both — each is discovered and run
independently.

### Timed benchmarks

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

```dart
import 'package:benchmark_infrastructure/benchmark_infrastructure.dart';

class MyMemoryBenchmark extends MemoryBenchmarkBase {
  MyMemoryBenchmark() : super('My memory benchmark name');

  @override
  Object? run() {
    final thing = buildTheThing();
    return thing; // measured
  }
}

Future<void> main() async {
  await MyMemoryBenchmark().report();
}
```

**`run()` must return what you want measured.** Measuring forces a GC, so
anything `run()` only kept in a local is already collectable garbage by the
time the heap is read. The returned value is parked in a GC root until after
the reading, which is what makes the number the retained size of the object
instead of leftover garbage. A benchmark that returns `null` measures noise.

`report()` calls `run()` once to warm up, then measures it 5 times and
reports the **median** delta. Pass `warmupRuns` / `samples` to change that.
Like the timed harness, this assumes `run()` is repeatable: a benchmark that
mutates a fixture built in `setup()` must pass `warmupRuns: 0, samples: 1`.

Measuring needs the Dart VM service (to force a GC and read real isolate heap
usage). `MemoryBenchmarkBase` starts it on demand, so a memory benchmark file
runs with a plain `dart run`, same as a timed one.


## Running

`melos run benchmark` runs every package with a `benchmarks/` folder. From
inside one such package, `dart run benchmark_infrastructure:run_benchmarks`
does the same for just that package: it discovers every
`benchmarks/src/timed/*_benchmark.dart` file and every
`benchmarks/src/memory/*_benchmark.dart` file, runs each as its own
subprocess (a fresh VM per file), and writes the aggregated results as
Markdown tables to `benchmarks/timed_results.md` and
`benchmarks/memory_results.md` respectively. 

A package missing one of the two subfolders just gets a note
on stderr for that half — the other still runs.

Both suites run by default. Pass `--no-timed` or `--no-memory` to
`run_benchmarks` to skip one, e.g. `dart run
benchmark_infrastructure:run_benchmarks --no-memory`.

Either half leaves its results file untouched when it collected no result at
all, so a run that fails outright can't wipe the committed baseline.

## Structure

`lib/src/timed/` is timing-specific.
`lib/src/memory/` mirrors it for RAM usage.
