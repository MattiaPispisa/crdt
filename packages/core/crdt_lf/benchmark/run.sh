#!/bin/bash
set -e

echo "Running benchmarks..."

# Clean up previous results
rm -f benchmark/results.md

# Run benchmarks and append results to a file
for benchmark in benchmark/src/benchmarks/*_benchmark.dart; do
  echo "  - 🔄 Running $benchmark"
  dart run "$benchmark" >> benchmark/results.md
  echo "  - ✅ Finished $benchmark"
done

echo "Benchmarks finished. Results are in benchmark/results.md"
