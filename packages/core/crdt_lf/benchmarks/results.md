### apply_changes_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Apply 1000 changes | 945.6669 | 0.9457 | 0.000946 |

### change_roundtrip_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Change toBytes x1000 | 59.2008 | 0.0592 | 0.000059 |
| Change fromBytes x1000 | 9057.4093 | 9.0574 | 0.009057 |
| Change roundtrip x1000 | 76.1034 | 0.0761 | 0.000076 |

### dag_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| DAG addNode chain of 1000 | 43188.4994 | 43.1885 | 0.043188 |
| DAG getAncestors chain of 200 | 7.1602 | 0.0072 | 0.000007 |

### fugue_list_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTFugueListHandler do 1000 operations and get value (incremental cache update: true) | 2851.7023 | 2.8517 | 0.002852 |

### fugue_snapshot_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text takeSnapshot of 10000 elements (tombstones: false) | 964.6246 | 0.9646 | 0.000965 |
| Fugue text restore of 10000 elements from snapshot (tombstones: false) | 1148.6130 | 1.1486 | 0.001149 |
| Fugue text takeSnapshot of 10000 elements (tombstones: true) | 1003.2680 | 1.0033 | 0.001003 |
| Fugue text restore of 10000 elements from snapshot (tombstones: true) | 29798.1483 | 29.7981 | 0.029798 |
| Fugue text takeSnapshot of 100000 elements (tombstones: false) | 27674.2429 | 27.6742 | 0.027674 |
| Fugue text restore of 100000 elements from snapshot (tombstones: false) | 26727.9200 | 26.7279 | 0.026728 |
| Fugue text takeSnapshot of 100000 elements (tombstones: true) | 38857.7100 | 38.8577 | 0.038858 |
| Fugue text restore of 100000 elements from snapshot (tombstones: true) | 14725.6250 | 14.7256 | 0.014726 |

### fugue_text_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text keystroke + length on 30000 chars | 5.8100 | 0.0058 | 0.000006 |
| Fugue text keystroke + value on 30000 chars | 325.8150 | 0.3258 | 0.000326 |
| Fugue text update on 30000 chars | 1.6300 | 0.0016 | 0.000002 |

### fugue_tree_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| FugueTree append 50000 elements | 9412.7773 | 9.4128 | 0.009413 |
| FugueTree prepend 50000 elements | 82343.2667 | 82.3433 | 0.082343 |
| FugueTree random insert 50000 elements | 98441.0500 | 98.4411 | 0.098441 |
| FugueTree values() over 50000 live elements | 358.3091 | 0.3583 | 0.000358 |
| FugueTree values() over 50000 elements, 90% tombstones | 60.7149 | 0.0607 | 0.000061 |

### hlc_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| HLC toUint8List x100k | 24.3777 | 0.0244 | 0.000024 |
| HLC fromUint8List x100k | 506.6882 | 0.5067 | 0.000507 |
| HLC compareTo x100k | 46.6854 | 0.0467 | 0.000047 |

### list_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTListHandler do 1000 operations and get value (incremental cache update: true) | 2456.6764 | 2.4567 | 0.002457 |

### map_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTMapHandler do 1000 operations and get value (incremental cache update: true) | 2381.4655 | 2.3815 | 0.002381 |

### nested_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Resolve nested tree with 50 leaves (cold caches) | 97.6169 | 0.0976 | 0.000098 |
| Resolve nested tree with 200 leaves (cold caches) | 419.4548 | 0.4195 | 0.000419 |
| Resolve nested tree with 800 leaves (cold caches) | 1805.5148 | 1.8055 | 0.001806 |
| Import + resolve nested tree with 50 leaves (fresh peer) | 354.4370 | 0.3544 | 0.000354 |
| Import + resolve nested tree with 200 leaves (fresh peer) | 1393.0362 | 1.3930 | 0.001393 |
| Import + resolve nested tree with 800 leaves (fresh peer) | 6522.8341 | 6.5228 | 0.006523 |

### op_id_key_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| OpIdKey view x100k | 484.8371 | 0.4848 | 0.000485 |
| OpIdKey hashCode x100k (cold) | 1959.2369 | 1.9592 | 0.001959 |
| OpIdKey map lookup x10k | 68.1670 | 0.0682 | 0.000068 |
| OperationId map lookup x10k | 64.2823 | 0.0643 | 0.000064 |

### or_set_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTORSetHandler do 1000 operations and get value (incremental cache update: true) | 2674.9493 | 2.6749 | 0.002675 |

### peer_id_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| PeerId generate x100 | 160.2115 | 0.1602 | 0.000160 |
| PeerId toUint8List x1000 | 31.7341 | 0.0317 | 0.000032 |
| PeerId fromUint8List x1000 | 52.5044 | 0.0525 | 0.000053 |

### remote_apply_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text remote keystroke + read on 2000 chars | 41.9250 | 0.0419 | 0.000042 |
| Fugue text remote keystroke + read on 10000 chars | 90.4500 | 0.0905 | 0.000090 |
| Fugue text remote keystroke + read on 30000 chars | 332.7100 | 0.3327 | 0.000333 |
| Text remote keystroke + read on 2000 chars | 9.2150 | 0.0092 | 0.000009 |
| Text remote keystroke + read on 10000 chars | 13.4650 | 0.0135 | 0.000013 |
| Text remote keystroke + read on 30000 chars | 18.3050 | 0.0183 | 0.000018 |
| Map remote set + read on 1000 keys | 8.8700 | 0.0089 | 0.000009 |
| Map remote set + read on 5000 keys | 4.8150 | 0.0048 | 0.000005 |
| OR-set remote add from the past + read on 1000 values | 27.9750 | 0.0280 | 0.000028 |
| OR-set remote add from the past + read on 5000 values | 96.6550 | 0.0967 | 0.000097 |
| OR-map remote put from the past + read on 1000 keys | 68.9800 | 0.0690 | 0.000069 |
| OR-map remote put from the past + read on 5000 keys | 234.2600 | 0.2343 | 0.000234 |
| Movable list remote move from the past + read on 1000 items | 46.2150 | 0.0462 | 0.000046 |
| Movable list remote move from the past + read on 5000 items | 166.6200 | 0.1666 | 0.000167 |

### scaling_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Import 1000 chained changes | 935.2703 | 0.9353 | 0.000935 |
| Import 10000 chained changes | 11086.4842 | 11.0865 | 0.011086 |
| exportChangesNewerThan on 50000 changes / 10 peers (99% caught-up) | 1.6282 | 0.0016 | 0.000002 |
| takeSnapshot(pruneHistory) with 10000 changes | 22031.0091 | 22.0310 | 0.022031 |
| takeSnapshot(pruneHistory) with 100 concurrent heads | 3771.5302 | 3.7715 | 0.003772 |

### serialization_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Binary encode/decode 1000 changes | 1442.6845 | 1.4427 | 0.001443 |

### snapshot_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Take snapshot with 1000 changes | 130.2315 | 0.1302 | 0.000130 |

### text_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTTextHandler do 1000 operations and get value (incremental cache update: true) | 2778.0534 | 2.7781 | 0.002778 |
| CRDTTextHandler do 1000 operations and get value (incremental cache update: false) | 2946.5311 | 2.9465 | 0.002947 |

### topological_sort_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Import 1000 concurrent changes | 945.4280 | 0.9454 | 0.000945 |

### version_vector_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| VersionVector toBytes 10 peers x1000 | 445.2026 | 0.4452 | 0.000445 |
| VersionVector fromBytes 10 peers x1000 | 647.6946 | 0.6477 | 0.000648 |
| VersionVector intersection 10 peers x1000 | 202.4626 | 0.2025 | 0.000202 |

