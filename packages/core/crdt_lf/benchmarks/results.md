### apply_changes_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Apply 1000 changes | 922.6734 | 0.9227 | 0.000923 |

### change_roundtrip_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Change toBytes x1000 | 59.9145 | 0.0599 | 0.000060 |
| Change fromBytes x1000 | 18.5152 | 0.0185 | 0.000019 |
| Change roundtrip x1000 | 79.3571 | 0.0794 | 0.000079 |

### dag_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| DAG addNode chain of 1000 | 182.0692 | 0.1821 | 0.000182 |
| DAG getAncestors chain of 200 | 7.8477 | 0.0078 | 0.000008 |

### delta_emission_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text remote keystroke + read on 2000 chars (watched: false) | 42.8000 | 0.0428 | 0.000043 |
| Fugue text remote keystroke + read on 2000 chars (watched: true) | 34.5200 | 0.0345 | 0.000035 |
| Fugue text remote keystroke + read on 10000 chars (watched: false) | 104.1150 | 0.1041 | 0.000104 |
| Fugue text remote keystroke + read on 10000 chars (watched: true) | 87.9250 | 0.0879 | 0.000088 |
| Text remote keystroke + read on 2000 chars (watched: false) | 9.7550 | 0.0098 | 0.000010 |
| Text remote keystroke + read on 2000 chars (watched: true) | 11.3500 | 0.0113 | 0.000011 |
| Text remote keystroke + read on 10000 chars (watched: false) | 12.7800 | 0.0128 | 0.000013 |
| Text remote keystroke + read on 10000 chars (watched: true) | 18.5800 | 0.0186 | 0.000019 |
| Map remote write + read on 1000 keys (watched: false) | 13.2250 | 0.0132 | 0.000013 |
| Map remote write + read on 1000 keys (watched: true) | 7.7700 | 0.0078 | 0.000008 |
| Map remote write + read on 5000 keys (watched: false) | 4.6900 | 0.0047 | 0.000005 |
| Map remote write + read on 5000 keys (watched: true) | 5.1050 | 0.0051 | 0.000005 |
| Fugue text type 2000 chars locally (watched: false) | 56448.4865 | 56.4485 | 0.056448 |
| Fugue text type 2000 chars locally (watched: true) | 72483.2308 | 72.4832 | 0.072483 |

### fugue_list_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTFugueListHandler do 1000 operations and get value (incremental cache update: true) | 3397.2935 | 3.3973 | 0.003397 |

### fugue_snapshot_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text takeSnapshot of 10000 elements (tombstones: false) | 1033.8275 | 1.0338 | 0.001034 |
| Fugue text restore of 10000 elements from snapshot (tombstones: false) | 1173.9796 | 1.1740 | 0.001174 |
| Fugue text takeSnapshot of 10000 elements (tombstones: true) | 1057.5640 | 1.0576 | 0.001058 |
| Fugue text restore of 10000 elements from snapshot (tombstones: true) | 1068.6508 | 1.0687 | 0.001069 |
| Fugue text takeSnapshot of 100000 elements (tombstones: false) | 34137.9167 | 34.1379 | 0.034138 |
| Fugue text restore of 100000 elements from snapshot (tombstones: false) | 23642.7687 | 23.6428 | 0.023643 |
| Fugue text takeSnapshot of 100000 elements (tombstones: true) | 55518.5750 | 55.5186 | 0.055519 |
| Fugue text restore of 100000 elements from snapshot (tombstones: true) | 14982.2125 | 14.9822 | 0.014982 |

### fugue_text_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text keystroke + length on 30000 chars | 6.5400 | 0.0065 | 0.000007 |
| Fugue text keystroke + value on 30000 chars | 324.0800 | 0.3241 | 0.000324 |
| Fugue text update on 30000 chars | 1.7550 | 0.0018 | 0.000002 |

### fugue_tree_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| FugueTree append 50000 elements | 9430.4500 | 9.4305 | 0.009430 |
| FugueTree prepend 50000 elements | 81506.4667 | 81.5065 | 0.081506 |
| FugueTree random insert 50000 elements | 102010.0500 | 102.0101 | 0.102010 |
| FugueTree values() over 50000 live elements | 375.3608 | 0.3754 | 0.000375 |
| FugueTree values() over 50000 elements, 90% tombstones | 61.9239 | 0.0619 | 0.000062 |

### hlc_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| HLC toUint8List x100k | 24.8837 | 0.0249 | 0.000025 |
| HLC fromUint8List x100k | 513.7473 | 0.5137 | 0.000514 |
| HLC compareTo x100k | 46.4109 | 0.0464 | 0.000046 |

### list_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTListHandler do 1000 operations and get value (incremental cache update: true) | 2473.8574 | 2.4739 | 0.002474 |

### map_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTMapHandler do 1000 operations and get value (incremental cache update: true) | 2420.5047 | 2.4205 | 0.002421 |

### nested_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Resolve nested tree with 50 leaves (cold caches) | 98.7981 | 0.0988 | 0.000099 |
| Resolve nested tree with 200 leaves (cold caches) | 433.8106 | 0.4338 | 0.000434 |
| Resolve nested tree with 800 leaves (cold caches) | 1814.9589 | 1.8150 | 0.001815 |
| Import + resolve nested tree with 50 leaves (fresh peer) | 354.5412 | 0.3545 | 0.000355 |
| Import + resolve nested tree with 200 leaves (fresh peer) | 1401.3007 | 1.4013 | 0.001401 |
| Import + resolve nested tree with 800 leaves (fresh peer) | 6675.5091 | 6.6755 | 0.006676 |

### op_id_key_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| OpIdKey view x100k | 479.0962 | 0.4791 | 0.000479 |
| OpIdKey hashCode x100k (cold) | 1939.2613 | 1.9393 | 0.001939 |
| OpIdKey map lookup x10k | 68.9399 | 0.0689 | 0.000069 |
| OperationId map lookup x10k | 59.1558 | 0.0592 | 0.000059 |

### or_set_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTORSetHandler do 1000 operations and get value (incremental cache update: true) | 2772.1391 | 2.7721 | 0.002772 |

### peer_id_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| PeerId generate x100 | 168.0333 | 0.1680 | 0.000168 |
| PeerId toUint8List x1000 | 32.6489 | 0.0326 | 0.000033 |
| PeerId fromUint8List x1000 | 54.1321 | 0.0541 | 0.000054 |

### remote_apply_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text remote keystroke + read on 2000 chars | 41.8150 | 0.0418 | 0.000042 |
| Fugue text remote keystroke + read on 10000 chars | 92.6200 | 0.0926 | 0.000093 |
| Fugue text remote keystroke + read on 30000 chars | 337.3900 | 0.3374 | 0.000337 |
| Text remote keystroke + read on 2000 chars | 9.3800 | 0.0094 | 0.000009 |
| Text remote keystroke + read on 10000 chars | 14.6250 | 0.0146 | 0.000015 |
| Text remote keystroke + read on 30000 chars | 18.6800 | 0.0187 | 0.000019 |
| Map remote set + read on 1000 keys | 8.2150 | 0.0082 | 0.000008 |
| Map remote set + read on 5000 keys | 4.7800 | 0.0048 | 0.000005 |
| OR-set remote add from the past + read on 1000 values | 28.0700 | 0.0281 | 0.000028 |
| OR-set remote add from the past + read on 5000 values | 94.6550 | 0.0947 | 0.000095 |
| OR-map remote put from the past + read on 1000 keys | 69.0200 | 0.0690 | 0.000069 |
| OR-map remote put from the past + read on 5000 keys | 239.2500 | 0.2392 | 0.000239 |
| Movable list remote move from the past + read on 1000 items | 46.8150 | 0.0468 | 0.000047 |
| Movable list remote move from the past + read on 5000 items | 169.4950 | 0.1695 | 0.000169 |

### scaling_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Import 1000 chained changes | 923.5335 | 0.9235 | 0.000924 |
| Import 10000 chained changes | 10976.1450 | 10.9761 | 0.010976 |
| exportChangesNewerThan on 50000 changes / 10 peers (99% caught-up) | 1.5908 | 0.0016 | 0.000002 |
| takeSnapshot(pruneHistory) with 10000 changes | 23054.3700 | 23.0544 | 0.023054 |
| takeSnapshot(pruneHistory) with 100 concurrent heads | 4177.0204 | 4.1770 | 0.004177 |

### serialization_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Binary encode/decode 1000 changes | 1479.1023 | 1.4791 | 0.001479 |

### snapshot_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Take snapshot with 1000 changes | 129.1572 | 0.1292 | 0.000129 |

### text_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTTextHandler do 1000 operations and get value (incremental cache update: true) | 2774.8342 | 2.7748 | 0.002775 |
| CRDTTextHandler do 1000 operations and get value (incremental cache update: false) | 2861.4894 | 2.8615 | 0.002861 |

### topological_sort_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Import 1000 concurrent changes | 936.6962 | 0.9367 | 0.000937 |

### version_vector_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| VersionVector toBytes 10 peers x1000 | 440.3776 | 0.4404 | 0.000440 |
| VersionVector fromBytes 10 peers x1000 | 651.0084 | 0.6510 | 0.000651 |
| VersionVector intersection 10 peers x1000 | 201.8351 | 0.2018 | 0.000202 |

