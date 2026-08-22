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

Memory subprocesses are launched with `dart run --enable-vm-service=0
--no-pause-isolates-on-exit`: port `0` picks an unused port so back-to-back
runs never collide, and `--no-pause-isolates-on-exit` stops the isolate from
pausing for a debugger on exit, so the subprocess still terminates on its
own once `main()` returns.

## Structure

`lib/src/timed/` is timing-specific.
`lib/src/memory/` mirrors it for RAM usage.
