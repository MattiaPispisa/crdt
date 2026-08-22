### apply_changes_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Apply 1000 changes | 984.5840 | 0.9846 | 0.000985 |

### change_roundtrip_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Change toBytes x1000 | 62.1767 | 0.0622 | 0.000062 |
| Change fromBytes x1000 | 22.0586 | 0.0221 | 0.000022 |
| Change roundtrip x1000 | 89.5785 | 0.0896 | 0.000090 |

### dag_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| DAG addNode chain of 1000 | 183.5214 | 0.1835 | 0.000184 |
| DAG getAncestors chain of 200 | 7.6067 | 0.0076 | 0.000008 |

### fugue_list_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTFugueListHandler do 1000 operations and get value (incremental cache update: true) | 3222.6379 | 3.2226 | 0.003223 |

### fugue_snapshot_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text takeSnapshot of 10000 elements (tombstones: false) | 1163.3540 | 1.1634 | 0.001163 |
| Fugue text restore of 10000 elements from snapshot (tombstones: false) | 4335.9566 | 4.3360 | 0.004336 |
| Fugue text takeSnapshot of 10000 elements (tombstones: true) | 1253.3856 | 1.2534 | 0.001253 |
| Fugue text restore of 10000 elements from snapshot (tombstones: true) | 4643.7092 | 4.6437 | 0.004644 |
| Fugue text takeSnapshot of 100000 elements (tombstones: false) | 41024.5625 | 41.0246 | 0.041025 |
| Fugue text restore of 100000 elements from snapshot (tombstones: false) | 91306.6500 | 91.3066 | 0.091307 |
| Fugue text takeSnapshot of 100000 elements (tombstones: true) | 45246.1000 | 45.2461 | 0.045246 |
| Fugue text restore of 100000 elements from snapshot (tombstones: true) | 126180.5500 | 126.1805 | 0.126181 |

### fugue_text_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text keystroke + length on 30000 chars | 3.1550 | 0.0032 | 0.000003 |
| Fugue text keystroke + value on 30000 chars | 646.8600 | 0.6469 | 0.000647 |
| Fugue text update on 30000 chars | 2.1350 | 0.0021 | 0.000002 |

### fugue_tree_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| FugueTree append 50000 elements | 30746.0571 | 30.7461 | 0.030746 |
| FugueTree prepend 50000 elements | 75883.7333 | 75.8837 | 0.075884 |
| FugueTree random insert 50000 elements | 78468.1667 | 78.4682 | 0.078468 |
| FugueTree values() over 50000 live elements | 845.0254 | 0.8450 | 0.000845 |
| FugueTree values() over 50000 elements, 90% tombstones | 135.1076 | 0.1351 | 0.000135 |

### hlc_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| HLC toUint8List x100k | 25.1596 | 0.0252 | 0.000025 |
| HLC fromUint8List x100k | 511.8858 | 0.5119 | 0.000512 |
| HLC compareTo x100k | 45.5149 | 0.0455 | 0.000046 |

### list_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTListHandler do 1000 operations and get value (incremental cache update: true) | 2654.0915 | 2.6541 | 0.002654 |

### map_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTMapHandler do 1000 operations and get value (incremental cache update: true) | 2636.4158 | 2.6364 | 0.002636 |

### nested_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Resolve nested tree with 50 leaves (cold caches) | 222.1717 | 0.2222 | 0.000222 |
| Resolve nested tree with 200 leaves (cold caches) | 940.2398 | 0.9402 | 0.000940 |
| Resolve nested tree with 800 leaves (cold caches) | 4209.0824 | 4.2091 | 0.004209 |
| Import + resolve nested tree with 50 leaves (fresh peer) | 586.3302 | 0.5863 | 0.000586 |
| Import + resolve nested tree with 200 leaves (fresh peer) | 2479.7083 | 2.4797 | 0.002480 |
| Import + resolve nested tree with 800 leaves (fresh peer) | 12180.8160 | 12.1808 | 0.012181 |

### op_id_key_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| OpIdKey view x100k | 481.3479 | 0.4813 | 0.000481 |
| OpIdKey hashCode x100k (cold) | 2158.1291 | 2.1581 | 0.002158 |
| OpIdKey map lookup x10k | 68.4141 | 0.0684 | 0.000068 |
| OperationId map lookup x10k | 60.3536 | 0.0604 | 0.000060 |

### or_set_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTORSetHandler do 1000 operations and get value (incremental cache update: true) | 2927.7507 | 2.9278 | 0.002928 |

### peer_id_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| PeerId generate x100 | 166.2783 | 0.1663 | 0.000166 |
| PeerId toUint8List x1000 | 32.8892 | 0.0329 | 0.000033 |
| PeerId fromUint8List x1000 | 59.7207 | 0.0597 | 0.000060 |

### remote_apply_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text remote keystroke + read on 2000 chars | 66.1550 | 0.0662 | 0.000066 |
| Fugue text remote keystroke + read on 10000 chars | 177.4800 | 0.1775 | 0.000177 |
| Fugue text remote keystroke + read on 30000 chars | 644.2050 | 0.6442 | 0.000644 |
| Text remote keystroke + read on 2000 chars | 10.8350 | 0.0108 | 0.000011 |
| Text remote keystroke + read on 10000 chars | 12.5450 | 0.0125 | 0.000013 |
| Text remote keystroke + read on 30000 chars | 18.6350 | 0.0186 | 0.000019 |
| Map remote set + read on 1000 keys | 16.5150 | 0.0165 | 0.000017 |
| Map remote set + read on 5000 keys | 10.3400 | 0.0103 | 0.000010 |
| OR-set remote add from the past + read on 1000 values | 34.4100 | 0.0344 | 0.000034 |
| OR-set remote add from the past + read on 5000 values | 116.0850 | 0.1161 | 0.000116 |
| OR-map remote put from the past + read on 1000 keys | 69.7900 | 0.0698 | 0.000070 |
| OR-map remote put from the past + read on 5000 keys | 275.0450 | 0.2750 | 0.000275 |
| Movable list remote move from the past + read on 1000 items | 42.2350 | 0.0422 | 0.000042 |
| Movable list remote move from the past + read on 5000 items | 158.7850 | 0.1588 | 0.000159 |

### scaling_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Import 1000 chained changes | 1003.3380 | 1.0033 | 0.001003 |
| Import 10000 chained changes | 11956.8000 | 11.9568 | 0.011957 |
| exportChangesNewerThan on 50000 changes / 10 peers (99% caught-up) | 1.6315 | 0.0016 | 0.000002 |
| takeSnapshot(pruneHistory) with 10000 changes | 29591.7200 | 29.5917 | 0.029592 |
| takeSnapshot(pruneHistory) with 100 concurrent heads | 3952.6269 | 3.9526 | 0.003953 |

### serialization_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Binary encode/decode 1000 changes | 1954.0628 | 1.9541 | 0.001954 |

### snapshot_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Take snapshot with 1000 changes | 136.3443 | 0.1363 | 0.000136 |

### text_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTTextHandler do 1000 operations and get value (incremental cache update: true) | 3107.1134 | 3.1071 | 0.003107 |
| CRDTTextHandler do 1000 operations and get value (incremental cache update: false) | 3039.0433 | 3.0390 | 0.003039 |

### topological_sort_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Import 1000 concurrent changes | 986.7988 | 0.9868 | 0.000987 |

### version_vector_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| VersionVector toBytes 10 peers x1000 | 448.1134 | 0.4481 | 0.000448 |
| VersionVector fromBytes 10 peers x1000 | 1477.4790 | 1.4775 | 0.001477 |
| VersionVector intersection 10 peers x1000 | 184.2262 | 0.1842 | 0.000184 |

