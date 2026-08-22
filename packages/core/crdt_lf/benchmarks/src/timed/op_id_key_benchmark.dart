import 'dart:typed_data';

import 'package:benchmark_infrastructure/benchmark_infrastructure.dart';
import 'package:crdt_lf/crdt_lf.dart';
import 'package:hlc_dart/hlc_dart.dart';

/// Benchmarks OpIdKey.view() creation
/// — zero-copy key wrapping an existing buffer.
class OpIdKeyViewBenchmark extends TimedBenchmarkBase {
  OpIdKeyViewBenchmark() : super('OpIdKey view x100k');

  late final List<Uint8List> buffers;

  @override
  void setup() {
    final peer = PeerId.generate();
    buffers = List.generate(
      100000,
      (i) =>
          OperationId(peer, HybridLogicalClock(l: i + 1, c: 0)).toUint8List(),
    );
  }

  @override
  void run() {
    for (final buf in buffers) {
      OpIdKey.view(buf);
    }
  }
}

/// Benchmarks OpIdKey.hashCode
/// — FNV-1a over 24 bytes (cached after first call).
class OpIdKeyHashBenchmark extends TimedBenchmarkBase {
  OpIdKeyHashBenchmark() : super('OpIdKey hashCode x100k (cold)');

  late final List<Uint8List> buffers;

  @override
  void setup() {
    final peer = PeerId.generate();
    buffers = List.generate(
      100000,
      (i) =>
          OperationId(peer, HybridLogicalClock(l: i + 1, c: 0)).toUint8List(),
    );
  }

  @override
  void run() {
    // Create a fresh key each time so hashCode is cold (not cached).
    for (final buf in buffers) {
      OpIdKey.view(buf).hashCode;
    }
  }
}

/// Benchmarks Map\<OpIdKey, int> lookup
/// — representative of ChangeStore access.
class OpIdKeyMapLookupBenchmark extends TimedBenchmarkBase {
  OpIdKeyMapLookupBenchmark() : super('OpIdKey map lookup x10k');

  late final Map<OpIdKey, int> map;
  late final List<OpIdKey> keys;

  @override
  void setup() {
    final peer = PeerId.generate();
    map = {};
    keys = [];
    for (var i = 0; i < 10000; i++) {
      final key = OpIdKey.copy(
        OperationId(peer, HybridLogicalClock(l: i + 1, c: 0)).toUint8List(),
      );
      map[key] = i;
      keys.add(key);
    }
  }

  @override
  void run() {
    for (final key in keys) {
      map.containsKey(key);
    }
  }
}

/// Benchmarks Map\<OperationId, int> lookup
/// — for comparison with OpIdKey.
class OperationIdMapLookupBenchmark extends TimedBenchmarkBase {
  OperationIdMapLookupBenchmark() : super('OperationId map lookup x10k');

  late final Map<OperationId, int> map;
  late final List<OperationId> ids;

  @override
  void setup() {
    final peer = PeerId.generate();
    map = {};
    ids = [];
    for (var i = 0; i < 10000; i++) {
      final id = OperationId(peer, HybridLogicalClock(l: i + 1, c: 0));
      map[id] = i;
      ids.add(id);
    }
  }

  @override
  void run() {
    for (final id in ids) {
      map.containsKey(id);
    }
  }
}

void main() {
  OpIdKeyViewBenchmark().report();
  OpIdKeyHashBenchmark().report();
  OpIdKeyMapLookupBenchmark().report();
  OperationIdMapLookupBenchmark().report();
}
