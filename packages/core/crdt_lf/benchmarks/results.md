### apply_changes_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Apply 1000 changes | 951.2633 | 0.9513 | 0.000951 |

### change_roundtrip_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Change toBytes x1000 | 61.0764 | 0.0611 | 0.000061 |
| Change fromBytes x1000 | 18.7105 | 0.0187 | 0.000019 |
| Change roundtrip x1000 | 82.3081 | 0.0823 | 0.000082 |

### dag_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| DAG addNode chain of 1000 | 174.9783 | 0.1750 | 0.000175 |
| DAG getAncestors chain of 200 | 7.4178 | 0.0074 | 0.000007 |

### delta_emission_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text remote keystroke + read on 2000 chars (watched: false) | 41.8950 | 0.0419 | 0.000042 |
| Fugue text remote keystroke + read on 2000 chars (watched: true) | 34.5300 | 0.0345 | 0.000035 |
| Fugue text remote keystroke + read on 10000 chars (watched: false) | 90.2800 | 0.0903 | 0.000090 |
| Fugue text remote keystroke + read on 10000 chars (watched: true) | 83.6000 | 0.0836 | 0.000084 |
| Text remote keystroke + read on 2000 chars (watched: false) | 9.2450 | 0.0092 | 0.000009 |
| Text remote keystroke + read on 2000 chars (watched: true) | 12.4200 | 0.0124 | 0.000012 |
| Text remote keystroke + read on 10000 chars (watched: false) | 10.5550 | 0.0106 | 0.000011 |
| Text remote keystroke + read on 10000 chars (watched: true) | 19.6700 | 0.0197 | 0.000020 |
| Map remote write + read on 1000 keys (watched: false) | 7.4900 | 0.0075 | 0.000007 |
| Map remote write + read on 1000 keys (watched: true) | 10.0450 | 0.0100 | 0.000010 |
| Map remote write + read on 5000 keys (watched: false) | 4.7000 | 0.0047 | 0.000005 |
| Map remote write + read on 5000 keys (watched: true) | 5.3550 | 0.0054 | 0.000005 |
| Movable list remote move + read on 1000 elements (watched: false) | 52.0850 | 0.0521 | 0.000052 |
| Movable list remote move + read on 1000 elements (watched: true) | 74.8100 | 0.0748 | 0.000075 |
| Movable list remote move + read on 5000 elements (watched: false) | 187.1500 | 0.1872 | 0.000187 |
| Movable list remote move + read on 5000 elements (watched: true) | 355.0950 | 0.3551 | 0.000355 |
| Fugue text type 2000 chars locally (watched: false) | 62957.6389 | 62.9576 | 0.062958 |
| Fugue text type 2000 chars locally (watched: true) | 85177.2273 | 85.1772 | 0.085177 |

### fugue_list_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTFugueListHandler do 1000 operations and get value (incremental cache update: true) | 3237.6125 | 3.2376 | 0.003238 |

### fugue_snapshot_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text takeSnapshot of 10000 elements (tombstones: false) | 1051.9640 | 1.0520 | 0.001052 |
| Fugue text restore of 10000 elements from snapshot (tombstones: false) | 1308.7712 | 1.3088 | 0.001309 |
| Fugue text takeSnapshot of 10000 elements (tombstones: true) | 1092.7487 | 1.0927 | 0.001093 |
| Fugue text restore of 10000 elements from snapshot (tombstones: true) | 1352.4041 | 1.3524 | 0.001352 |
| Fugue text takeSnapshot of 100000 elements (tombstones: false) | 31974.0909 | 31.9741 | 0.031974 |
| Fugue text restore of 100000 elements from snapshot (tombstones: false) | 23244.2071 | 23.2442 | 0.023244 |
| Fugue text takeSnapshot of 100000 elements (tombstones: true) | 52436.6250 | 52.4366 | 0.052437 |
| Fugue text restore of 100000 elements from snapshot (tombstones: true) | 14042.8267 | 14.0428 | 0.014043 |

### fugue_text_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text keystroke + length on 30000 chars | 13.6350 | 0.0136 | 0.000014 |
| Fugue text keystroke + value on 30000 chars | 325.5450 | 0.3255 | 0.000326 |
| Fugue text update on 30000 chars | 1.6900 | 0.0017 | 0.000002 |

### fugue_tree_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| FugueTree append 50000 elements | 11015.1632 | 11.0152 | 0.011015 |
| FugueTree prepend 50000 elements | 100827.9000 | 100.8279 | 0.100828 |
| FugueTree random insert 50000 elements | 120768.0000 | 120.7680 | 0.120768 |
| FugueTree values() over 50000 live elements | 375.9187 | 0.3759 | 0.000376 |
| FugueTree values() over 50000 elements, 90% tombstones | 62.7264 | 0.0627 | 0.000063 |

### hlc_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| HLC toUint8List x100k | 24.6837 | 0.0247 | 0.000025 |
| HLC fromUint8List x100k | 517.0050 | 0.5170 | 0.000517 |
| HLC compareTo x100k | 45.6921 | 0.0457 | 0.000046 |

### list_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTListHandler do 1000 operations and get value (incremental cache update: true) | 2442.7182 | 2.4427 | 0.002443 |

### map_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTMapHandler do 1000 operations and get value (incremental cache update: true) | 2614.3701 | 2.6144 | 0.002614 |

### nested_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Resolve nested tree with 50 leaves (cold caches) | 110.7708 | 0.1108 | 0.000111 |
| Resolve nested tree with 200 leaves (cold caches) | 488.0908 | 0.4881 | 0.000488 |
| Resolve nested tree with 800 leaves (cold caches) | 1975.4375 | 1.9754 | 0.001975 |
| Import + resolve nested tree with 50 leaves (fresh peer) | 397.8477 | 0.3978 | 0.000398 |
| Import + resolve nested tree with 200 leaves (fresh peer) | 1554.5484 | 1.5545 | 0.001555 |
| Import + resolve nested tree with 800 leaves (fresh peer) | 6125.6167 | 6.1256 | 0.006126 |

### op_id_key_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| OpIdKey view x100k | 484.4658 | 0.4845 | 0.000484 |
| OpIdKey hashCode x100k (cold) | 1848.1143 | 1.8481 | 0.001848 |
| OpIdKey map lookup x10k | 70.7404 | 0.0707 | 0.000071 |
| OperationId map lookup x10k | 65.1054 | 0.0651 | 0.000065 |

### or_set_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTORSetHandler do 1000 operations and get value (incremental cache update: true) | 2905.0026 | 2.9050 | 0.002905 |

### peer_id_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| PeerId generate x100 | 164.8645 | 0.1649 | 0.000165 |
| PeerId toUint8List x1000 | 32.0435 | 0.0320 | 0.000032 |
| PeerId fromUint8List x1000 | 54.5756 | 0.0546 | 0.000055 |

### remote_apply_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text remote keystroke + read on 2000 chars | 41.9450 | 0.0419 | 0.000042 |
| Fugue text remote keystroke + read on 10000 chars | 93.8250 | 0.0938 | 0.000094 |
| Fugue text remote keystroke + read on 30000 chars | 322.2050 | 0.3222 | 0.000322 |
| Text remote keystroke + read on 2000 chars | 9.7150 | 0.0097 | 0.000010 |
| Text remote keystroke + read on 10000 chars | 12.4100 | 0.0124 | 0.000012 |
| Text remote keystroke + read on 30000 chars | 17.2300 | 0.0172 | 0.000017 |
| Map remote set + read on 1000 keys | 12.0300 | 0.0120 | 0.000012 |
| Map remote set + read on 5000 keys | 11.8800 | 0.0119 | 0.000012 |
| OR-set remote add from the past + read on 1000 values | 44.0250 | 0.0440 | 0.000044 |
| OR-set remote add from the past + read on 5000 values | 92.6400 | 0.0926 | 0.000093 |
| OR-map remote put from the past + read on 1000 keys | 58.6450 | 0.0586 | 0.000059 |
| OR-map remote put from the past + read on 5000 keys | 233.5400 | 0.2335 | 0.000234 |
| Movable list remote move from the past + read on 1000 items | 46.3300 | 0.0463 | 0.000046 |
| Movable list remote move from the past + read on 5000 items | 174.0200 | 0.1740 | 0.000174 |

### scaling_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Import 1000 chained changes | 951.9770 | 0.9520 | 0.000952 |
| Import 10000 chained changes | 11688.6348 | 11.6886 | 0.011689 |
| exportChangesNewerThan on 50000 changes / 10 peers (99% caught-up) | 1.9312 | 0.0019 | 0.000002 |
| takeSnapshot(pruneHistory) with 10000 changes | 27311.5000 | 27.3115 | 0.027311 |
| takeSnapshot(pruneHistory) with 100 concurrent heads | 4025.1149 | 4.0251 | 0.004025 |

### serialization_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Binary encode/decode 1000 changes | 1483.4269 | 1.4834 | 0.001483 |

### snapshot_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Take snapshot with 1000 changes | 132.5393 | 0.1325 | 0.000133 |

### text_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTTextHandler do 1000 operations and get value (incremental cache update: true) | 2885.6645 | 2.8857 | 0.002886 |
| CRDTTextHandler do 1000 operations and get value (incremental cache update: false) | 3008.6198 | 3.0086 | 0.003009 |

### topological_sort_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Import 1000 concurrent changes | 946.1235 | 0.9461 | 0.000946 |

### undo_manager_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text type 300 chars locally (undo managers: 0) | 737.2333 | 0.7372 | 0.000737 |
| Fugue text type 300 chars locally (undo managers: 1) | 795.2000 | 0.7952 | 0.000795 |
| Fugue text type 300 chars locally (undo managers: 2) | 863.1333 | 0.8631 | 0.000863 |
| Fugue text type 300 chars locally (undo managers: 3) | 873.5667 | 0.8736 | 0.000874 |
| Fugue text type 300 chars locally (undo managers: 5) | 906.8000 | 0.9068 | 0.000907 |
| Fugue text undo+redo one keystroke on 2000 chars | 13.6000 | 0.0136 | 0.000014 |
| Fugue text undo+redo one keystroke on 10000 chars | 4.5000 | 0.0045 | 0.000005 |
| Fugue text undo+redo a 1-char delete on 5000 chars | 4.4500 | 0.0044 | 0.000004 |
| Fugue text undo+redo a 100-char delete on 5000 chars | 58.4000 | 0.0584 | 0.000058 |
| Fugue text undo+redo a 500-char delete on 5000 chars | 350.4500 | 0.3504 | 0.000350 |
| Map undo+redo one set on 5000 keys | 3.8500 | 0.0039 | 0.000004 |
| OR-set undo+redo one add on 5000 values | 4.7500 | 0.0047 | 0.000005 |
| Fugue text undo/redo ping-pong x10 on 2000 chars | 475.6667 | 0.4757 | 0.000476 |
| Fugue text undo/redo ping-pong x100 on 2000 chars | 1367.6667 | 1.3677 | 0.001368 |
| Fugue text undo/redo ping-pong x1000 on 2000 chars | 12466.6667 | 12.4667 | 0.012467 |

### version_vector_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| VersionVector toBytes 10 peers x1000 | 418.3634 | 0.4184 | 0.000418 |
| VersionVector fromBytes 10 peers x1000 | 650.2140 | 0.6502 | 0.000650 |
| VersionVector intersection 10 peers x1000 | 202.2140 | 0.2022 | 0.000202 |

