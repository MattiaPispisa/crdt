### apply_changes_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Apply 1000 changes | 942.9754 | 0.9430 | 0.000943 |

### change_roundtrip_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Change toBytes x1000 | 59.0932 | 0.0591 | 0.000059 |
| Change fromBytes x1000 | 19.0283 | 0.0190 | 0.000019 |
| Change roundtrip x1000 | 79.0905 | 0.0791 | 0.000079 |

### dag_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| DAG addNode chain of 1000 | 171.9261 | 0.1719 | 0.000172 |
| DAG getAncestors chain of 200 | 7.6416 | 0.0076 | 0.000008 |

### fugue_list_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTFugueListHandler do 1000 operations and get value (incremental cache update: true) | 3046.1882 | 3.0462 | 0.003046 |

### fugue_snapshot_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text takeSnapshot of 10000 elements (tombstones: false) | 1168.2322 | 1.1682 | 0.001168 |
| Fugue text restore of 10000 elements from snapshot (tombstones: false) | 3390.5564 | 3.3906 | 0.003391 |
| Fugue text takeSnapshot of 10000 elements (tombstones: true) | 1257.8864 | 1.2579 | 0.001258 |
| Fugue text restore of 10000 elements from snapshot (tombstones: true) | 3912.3747 | 3.9124 | 0.003912 |
| Fugue text takeSnapshot of 100000 elements (tombstones: false) | 30691.3875 | 30.6914 | 0.030691 |
| Fugue text restore of 100000 elements from snapshot (tombstones: false) | 57147.1333 | 57.1471 | 0.057147 |
| Fugue text takeSnapshot of 100000 elements (tombstones: true) | 49008.1889 | 49.0082 | 0.049008 |
| Fugue text restore of 100000 elements from snapshot (tombstones: true) | 93329.0000 | 93.3290 | 0.093329 |

### fugue_text_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text keystroke + length on 30000 chars | 2.9900 | 0.0030 | 0.000003 |
| Fugue text keystroke + value on 30000 chars | 603.4000 | 0.6034 | 0.000603 |
| Fugue text update on 30000 chars | 2.1100 | 0.0021 | 0.000002 |

### fugue_tree_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| FugueTree append 50000 elements | 30138.2571 | 30.1383 | 0.030138 |
| FugueTree prepend 50000 elements | 75347.0333 | 75.3470 | 0.075347 |
| FugueTree random insert 50000 elements | 77029.1000 | 77.0291 | 0.077029 |
| FugueTree values() over 50000 live elements | 790.6843 | 0.7907 | 0.000791 |
| FugueTree values() over 50000 elements, 90% tombstones | 137.0269 | 0.1370 | 0.000137 |

### hlc_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| HLC toUint8List x100k | 24.5187 | 0.0245 | 0.000025 |
| HLC fromUint8List x100k | 507.6385 | 0.5076 | 0.000508 |
| HLC compareTo x100k | 45.1050 | 0.0451 | 0.000045 |

### list_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTListHandler do 1000 operations and get value (incremental cache update: true) | 2600.1934 | 2.6002 | 0.002600 |

### map_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTMapHandler do 1000 operations and get value (incremental cache update: true) | 2611.8091 | 2.6118 | 0.002612 |

### nested_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Resolve nested tree with 50 leaves (cold caches) | 196.5061 | 0.1965 | 0.000197 |
| Resolve nested tree with 200 leaves (cold caches) | 850.3703 | 0.8504 | 0.000850 |
| Resolve nested tree with 800 leaves (cold caches) | 3590.6333 | 3.5906 | 0.003591 |
| Import + resolve nested tree with 50 leaves (fresh peer) | 547.1873 | 0.5472 | 0.000547 |
| Import + resolve nested tree with 200 leaves (fresh peer) | 2309.0883 | 2.3091 | 0.002309 |
| Import + resolve nested tree with 800 leaves (fresh peer) | 9129.2241 | 9.1292 | 0.009129 |

### op_id_key_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| OpIdKey view x100k | 480.5094 | 0.4805 | 0.000481 |
| OpIdKey hashCode x100k (cold) | 1942.8189 | 1.9428 | 0.001943 |
| OpIdKey map lookup x10k | 67.9025 | 0.0679 | 0.000068 |
| OperationId map lookup x10k | 60.2593 | 0.0603 | 0.000060 |

### or_set_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTORSetHandler do 1000 operations and get value (incremental cache update: true) | 2900.0130 | 2.9000 | 0.002900 |

### peer_id_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| PeerId generate x100 | 164.0822 | 0.1641 | 0.000164 |
| PeerId toUint8List x1000 | 31.9681 | 0.0320 | 0.000032 |
| PeerId fromUint8List x1000 | 58.2138 | 0.0582 | 0.000058 |

### remote_apply_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text remote keystroke + read on 2000 chars | 62.2150 | 0.0622 | 0.000062 |
| Fugue text remote keystroke + read on 10000 chars | 168.2150 | 0.1682 | 0.000168 |
| Fugue text remote keystroke + read on 30000 chars | 679.8300 | 0.6798 | 0.000680 |
| Text remote keystroke + read on 2000 chars | 9.3000 | 0.0093 | 0.000009 |
| Text remote keystroke + read on 10000 chars | 11.6800 | 0.0117 | 0.000012 |
| Text remote keystroke + read on 30000 chars | 18.9700 | 0.0190 | 0.000019 |
| Map remote set + read on 1000 keys | 14.0850 | 0.0141 | 0.000014 |
| Map remote set + read on 5000 keys | 13.7150 | 0.0137 | 0.000014 |
| OR-set remote add from the past + read on 1000 values | 28.9200 | 0.0289 | 0.000029 |
| OR-set remote add from the past + read on 5000 values | 117.8000 | 0.1178 | 0.000118 |
| OR-map remote put from the past + read on 1000 keys | 71.0300 | 0.0710 | 0.000071 |
| OR-map remote put from the past + read on 5000 keys | 253.2950 | 0.2533 | 0.000253 |
| Movable list remote move from the past + read on 1000 items | 42.2900 | 0.0423 | 0.000042 |
| Movable list remote move from the past + read on 5000 items | 156.7250 | 0.1567 | 0.000157 |

### scaling_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Import 1000 chained changes | 947.4225 | 0.9474 | 0.000947 |
| Import 10000 chained changes | 11464.0522 | 11.4641 | 0.011464 |
| exportChangesNewerThan on 50000 changes / 10 peers (99% caught-up) | 1.6008 | 0.0016 | 0.000002 |
| takeSnapshot(pruneHistory) with 10000 changes | 24849.7600 | 24.8498 | 0.024850 |
| takeSnapshot(pruneHistory) with 100 concurrent heads | 3839.8865 | 3.8399 | 0.003840 |

### serialization_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Binary encode/decode 1000 changes | 1987.6339 | 1.9876 | 0.001988 |

### snapshot_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Take snapshot with 1000 changes | 130.2869 | 0.1303 | 0.000130 |

### text_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTTextHandler do 1000 operations and get value (incremental cache update: true) | 2985.9908 | 2.9860 | 0.002986 |
| CRDTTextHandler do 1000 operations and get value (incremental cache update: false) | 2840.6725 | 2.8407 | 0.002841 |

### topological_sort_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Import 1000 concurrent changes | 983.1307 | 0.9831 | 0.000983 |

### version_vector_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| VersionVector toBytes 10 peers x1000 | 448.7418 | 0.4487 | 0.000449 |
| VersionVector fromBytes 10 peers x1000 | 1485.4522 | 1.4855 | 0.001485 |
| VersionVector intersection 10 peers x1000 | 179.0403 | 0.1790 | 0.000179 |

