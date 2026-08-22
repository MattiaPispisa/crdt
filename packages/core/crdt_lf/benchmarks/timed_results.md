### apply_changes_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Apply 1000 changes | 940.3036 | 0.9403 | 0.000940 |

### change_roundtrip_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Change toBytes x1000 | 60.1395 | 0.0601 | 0.000060 |
| Change fromBytes x1000 | 18.9636 | 0.0190 | 0.000019 |
| Change roundtrip x1000 | 82.1582 | 0.0822 | 0.000082 |

### dag_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| DAG addNode chain of 1000 | 185.2616 | 0.1853 | 0.000185 |
| DAG getAncestors chain of 200 | 7.5396 | 0.0075 | 0.000008 |

### fugue_list_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTFugueListHandler do 1000 operations and get value (incremental cache update: true) | 3160.7382 | 3.1607 | 0.003161 |

### fugue_snapshot_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text takeSnapshot of 10000 elements (tombstones: false) | 1161.0971 | 1.1611 | 0.001161 |
| Fugue text restore of 10000 elements from snapshot (tombstones: false) | 5228.1767 | 5.2282 | 0.005228 |
| Fugue text takeSnapshot of 10000 elements (tombstones: true) | 1271.4056 | 1.2714 | 0.001271 |
| Fugue text restore of 10000 elements from snapshot (tombstones: true) | 4356.5475 | 4.3565 | 0.004357 |
| Fugue text takeSnapshot of 100000 elements (tombstones: false) | 30093.5167 | 30.0935 | 0.030094 |
| Fugue text restore of 100000 elements from snapshot (tombstones: false) | 111630.0500 | 111.6300 | 0.111630 |
| Fugue text takeSnapshot of 100000 elements (tombstones: true) | 43645.4500 | 43.6454 | 0.043645 |
| Fugue text restore of 100000 elements from snapshot (tombstones: true) | 41688.9000 | 41.6889 | 0.041689 |

### fugue_text_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text keystroke + length on 30000 chars | 3.0550 | 0.0031 | 0.000003 |
| Fugue text keystroke + value on 30000 chars | 635.6050 | 0.6356 | 0.000636 |
| Fugue text update on 30000 chars | 2.1600 | 0.0022 | 0.000002 |

### fugue_tree_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| FugueTree append 50000 elements | 30603.9000 | 30.6039 | 0.030604 |
| FugueTree prepend 50000 elements | 74866.2667 | 74.8663 | 0.074866 |
| FugueTree random insert 50000 elements | 78641.6333 | 78.6416 | 0.078642 |
| FugueTree values() over 50000 live elements | 837.8312 | 0.8378 | 0.000838 |
| FugueTree values() over 50000 elements, 90% tombstones | 128.5878 | 0.1286 | 0.000129 |

### hlc_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| HLC toUint8List x100k | 24.8601 | 0.0249 | 0.000025 |
| HLC fromUint8List x100k | 498.7944 | 0.4988 | 0.000499 |
| HLC compareTo x100k | 45.2189 | 0.0452 | 0.000045 |

### list_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTListHandler do 1000 operations and get value (incremental cache update: true) | 2580.5026 | 2.5805 | 0.002581 |

### map_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTMapHandler do 1000 operations and get value (incremental cache update: true) | 2581.5848 | 2.5816 | 0.002582 |

### nested_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Resolve nested tree with 50 leaves (cold caches) | 202.6073 | 0.2026 | 0.000203 |
| Resolve nested tree with 200 leaves (cold caches) | 859.4229 | 0.8594 | 0.000859 |
| Resolve nested tree with 800 leaves (cold caches) | 3570.7672 | 3.5708 | 0.003571 |
| Import + resolve nested tree with 50 leaves (fresh peer) | 540.4122 | 0.5404 | 0.000540 |
| Import + resolve nested tree with 200 leaves (fresh peer) | 2178.0270 | 2.1780 | 0.002178 |
| Import + resolve nested tree with 800 leaves (fresh peer) | 12132.5208 | 12.1325 | 0.012133 |

### op_id_key_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| OpIdKey view x100k | 477.0348 | 0.4770 | 0.000477 |
| OpIdKey hashCode x100k (cold) | 1951.4612 | 1.9515 | 0.001951 |
| OpIdKey map lookup x10k | 66.4295 | 0.0664 | 0.000066 |
| OperationId map lookup x10k | 5088.7329 | 5.0887 | 0.005089 |

### or_set_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTORSetHandler do 1000 operations and get value (incremental cache update: true) | 2999.8930 | 2.9999 | 0.003000 |

### peer_id_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| PeerId generate x100 | 156.3750 | 0.1564 | 0.000156 |
| PeerId toUint8List x1000 | 30.8606 | 0.0309 | 0.000031 |
| PeerId fromUint8List x1000 | 58.2556 | 0.0583 | 0.000058 |

### remote_apply_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text remote keystroke + read on 2000 chars | 62.5600 | 0.0626 | 0.000063 |
| Fugue text remote keystroke + read on 10000 chars | 172.3700 | 0.1724 | 0.000172 |
| Fugue text remote keystroke + read on 30000 chars | 692.4050 | 0.6924 | 0.000692 |
| Text remote keystroke + read on 2000 chars | 10.4000 | 0.0104 | 0.000010 |
| Text remote keystroke + read on 10000 chars | 13.1950 | 0.0132 | 0.000013 |
| Text remote keystroke + read on 30000 chars | 29.2050 | 0.0292 | 0.000029 |
| Map remote set + read on 1000 keys | 9.5550 | 0.0096 | 0.000010 |
| Map remote set + read on 5000 keys | 9.8500 | 0.0098 | 0.000010 |
| OR-set remote add from the past + read on 1000 values | 36.9400 | 0.0369 | 0.000037 |
| OR-set remote add from the past + read on 5000 values | 123.7750 | 0.1238 | 0.000124 |
| OR-map remote put from the past + read on 1000 keys | 68.0450 | 0.0680 | 0.000068 |
| OR-map remote put from the past + read on 5000 keys | 274.3950 | 0.2744 | 0.000274 |
| Movable list remote move from the past + read on 1000 items | 40.8000 | 0.0408 | 0.000041 |
| Movable list remote move from the past + read on 5000 items | 154.9900 | 0.1550 | 0.000155 |

### scaling_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Import 1000 chained changes | 944.7411 | 0.9447 | 0.000945 |
| Import 10000 chained changes | 12870.3158 | 12.8703 | 0.012870 |
| exportChangesNewerThan on 50000 changes / 10 peers (99% caught-up) | 1.6289 | 0.0016 | 0.000002 |
| takeSnapshot(pruneHistory) with 10000 changes | 21436.0444 | 21.4360 | 0.021436 |
| takeSnapshot(pruneHistory) with 100 concurrent heads | 3866.7462 | 3.8667 | 0.003867 |

### serialization_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Binary encode/decode 1000 changes | 2013.8698 | 2.0139 | 0.002014 |

### snapshot_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Take snapshot with 1000 changes | 146.5977 | 0.1466 | 0.000147 |

### text_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTTextHandler do 1000 operations and get value (incremental cache update: true) | 3028.1672 | 3.0282 | 0.003028 |
| CRDTTextHandler do 1000 operations and get value (incremental cache update: false) | 3126.0957 | 3.1261 | 0.003126 |

### topological_sort_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Import 1000 concurrent changes | 999.9556 | 1.0000 | 0.001000 |

### version_vector_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| VersionVector toBytes 10 peers x1000 | 451.7682 | 0.4518 | 0.000452 |
| VersionVector fromBytes 10 peers x1000 | 1464.0406 | 1.4640 | 0.001464 |
| VersionVector intersection 10 peers x1000 | 257.6776 | 0.2577 | 0.000258 |

