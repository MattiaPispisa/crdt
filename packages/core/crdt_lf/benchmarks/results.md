### apply_changes_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Apply 1000 changes | 929.5700 | 0.9296 | 0.000930 |

### change_roundtrip_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Change toBytes x1000 | 62.1126 | 0.0621 | 0.000062 |
| Change fromBytes x1000 | 18.4886 | 0.0185 | 0.000018 |
| Change roundtrip x1000 | 80.9582 | 0.0810 | 0.000081 |

### dag_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| DAG addNode chain of 1000 | 183.5051 | 0.1835 | 0.000184 |
| DAG getAncestors chain of 200 | 7.5536 | 0.0076 | 0.000008 |

### delta_emission_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text remote keystroke + read on 2000 chars (watched: false) | 40.6600 | 0.0407 | 0.000041 |
| Fugue text remote keystroke + read on 2000 chars (watched: true) | 32.4100 | 0.0324 | 0.000032 |
| Fugue text remote keystroke + read on 10000 chars (watched: false) | 87.2000 | 0.0872 | 0.000087 |
| Fugue text remote keystroke + read on 10000 chars (watched: true) | 82.7250 | 0.0827 | 0.000083 |
| Text remote keystroke + read on 2000 chars (watched: false) | 8.8100 | 0.0088 | 0.000009 |
| Text remote keystroke + read on 2000 chars (watched: true) | 11.6150 | 0.0116 | 0.000012 |
| Text remote keystroke + read on 10000 chars (watched: false) | 11.9450 | 0.0119 | 0.000012 |
| Text remote keystroke + read on 10000 chars (watched: true) | 17.0900 | 0.0171 | 0.000017 |
| Map remote write + read on 1000 keys (watched: false) | 7.6650 | 0.0077 | 0.000008 |
| Map remote write + read on 1000 keys (watched: true) | 7.9750 | 0.0080 | 0.000008 |
| Map remote write + read on 5000 keys (watched: false) | 5.4500 | 0.0054 | 0.000005 |
| Map remote write + read on 5000 keys (watched: true) | 4.6800 | 0.0047 | 0.000005 |
| Fugue text type 2000 chars locally (watched: false) | 56379.2632 | 56.3793 | 0.056379 |
| Fugue text type 2000 chars locally (watched: true) | 75864.2750 | 75.8643 | 0.075864 |

### fugue_list_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTFugueListHandler do 1000 operations and get value (incremental cache update: true) | 2977.5194 | 2.9775 | 0.002978 |

### fugue_snapshot_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text takeSnapshot of 10000 elements (tombstones: false) | 1020.2915 | 1.0203 | 0.001020 |
| Fugue text restore of 10000 elements from snapshot (tombstones: false) | 1111.0140 | 1.1110 | 0.001111 |
| Fugue text takeSnapshot of 10000 elements (tombstones: true) | 1125.5099 | 1.1255 | 0.001126 |
| Fugue text restore of 10000 elements from snapshot (tombstones: true) | 1330.3378 | 1.3303 | 0.001330 |
| Fugue text takeSnapshot of 100000 elements (tombstones: false) | 39430.5100 | 39.4305 | 0.039431 |
| Fugue text restore of 100000 elements from snapshot (tombstones: false) | 22141.7600 | 22.1418 | 0.022142 |
| Fugue text takeSnapshot of 100000 elements (tombstones: true) | 36169.4300 | 36.1694 | 0.036169 |
| Fugue text restore of 100000 elements from snapshot (tombstones: true) | 13968.3312 | 13.9683 | 0.013968 |

### fugue_text_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text keystroke + length on 30000 chars | 13.1250 | 0.0131 | 0.000013 |
| Fugue text keystroke + value on 30000 chars | 342.3300 | 0.3423 | 0.000342 |
| Fugue text update on 30000 chars | 1.6600 | 0.0017 | 0.000002 |

### fugue_tree_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| FugueTree append 50000 elements | 10894.2368 | 10.8942 | 0.010894 |
| FugueTree prepend 50000 elements | 94512.5500 | 94.5126 | 0.094513 |
| FugueTree random insert 50000 elements | 120467.4500 | 120.4674 | 0.120467 |
| FugueTree values() over 50000 live elements | 362.9381 | 0.3629 | 0.000363 |
| FugueTree values() over 50000 elements, 90% tombstones | 76.6536 | 0.0767 | 0.000077 |

### hlc_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| HLC toUint8List x100k | 25.1049 | 0.0251 | 0.000025 |
| HLC fromUint8List x100k | 512.8737 | 0.5129 | 0.000513 |
| HLC compareTo x100k | 51.1198 | 0.0511 | 0.000051 |

### list_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTListHandler do 1000 operations and get value (incremental cache update: true) | 2468.3118 | 2.4683 | 0.002468 |

### map_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTMapHandler do 1000 operations and get value (incremental cache update: true) | 2530.2253 | 2.5302 | 0.002530 |

### nested_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Resolve nested tree with 50 leaves (cold caches) | 122.1894 | 0.1222 | 0.000122 |
| Resolve nested tree with 200 leaves (cold caches) | 478.5807 | 0.4786 | 0.000479 |
| Resolve nested tree with 800 leaves (cold caches) | 2352.4458 | 2.3524 | 0.002352 |
| Import + resolve nested tree with 50 leaves (fresh peer) | 414.0280 | 0.4140 | 0.000414 |
| Import + resolve nested tree with 200 leaves (fresh peer) | 1597.2806 | 1.5973 | 0.001597 |
| Import + resolve nested tree with 800 leaves (fresh peer) | 6794.8744 | 6.7949 | 0.006795 |

### op_id_key_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| OpIdKey view x100k | 550.7335 | 0.5507 | 0.000551 |
| OpIdKey hashCode x100k (cold) | 1865.4156 | 1.8654 | 0.001865 |
| OpIdKey map lookup x10k | 67.1337 | 0.0671 | 0.000067 |
| OperationId map lookup x10k | 61.4094 | 0.0614 | 0.000061 |

### or_set_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTORSetHandler do 1000 operations and get value (incremental cache update: true) | 2735.7390 | 2.7357 | 0.002736 |

### peer_id_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| PeerId generate x100 | 162.6501 | 0.1627 | 0.000163 |
| PeerId toUint8List x1000 | 32.6074 | 0.0326 | 0.000033 |
| PeerId fromUint8List x1000 | 67.5336 | 0.0675 | 0.000068 |

### remote_apply_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text remote keystroke + read on 2000 chars | 45.3100 | 0.0453 | 0.000045 |
| Fugue text remote keystroke + read on 10000 chars | 95.1000 | 0.0951 | 0.000095 |
| Fugue text remote keystroke + read on 30000 chars | 323.3750 | 0.3234 | 0.000323 |
| Text remote keystroke + read on 2000 chars | 9.8700 | 0.0099 | 0.000010 |
| Text remote keystroke + read on 10000 chars | 13.5800 | 0.0136 | 0.000014 |
| Text remote keystroke + read on 30000 chars | 26.0300 | 0.0260 | 0.000026 |
| Map remote set + read on 1000 keys | 9.5900 | 0.0096 | 0.000010 |
| Map remote set + read on 5000 keys | 5.0700 | 0.0051 | 0.000005 |
| OR-set remote add from the past + read on 1000 values | 36.0700 | 0.0361 | 0.000036 |
| OR-set remote add from the past + read on 5000 values | 100.3450 | 0.1003 | 0.000100 |
| OR-map remote put from the past + read on 1000 keys | 59.0650 | 0.0591 | 0.000059 |
| OR-map remote put from the past + read on 5000 keys | 243.9500 | 0.2440 | 0.000244 |
| Movable list remote move from the past + read on 1000 items | 45.3000 | 0.0453 | 0.000045 |
| Movable list remote move from the past + read on 5000 items | 173.8100 | 0.1738 | 0.000174 |

### scaling_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Import 1000 chained changes | 961.6108 | 0.9616 | 0.000962 |
| Import 10000 chained changes | 11500.1286 | 11.5001 | 0.011500 |
| exportChangesNewerThan on 50000 changes / 10 peers (99% caught-up) | 1.9673 | 0.0020 | 0.000002 |
| takeSnapshot(pruneHistory) with 10000 changes | 24419.8800 | 24.4199 | 0.024420 |
| takeSnapshot(pruneHistory) with 100 concurrent heads | 3884.1900 | 3.8842 | 0.003884 |

### serialization_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Binary encode/decode 1000 changes | 1525.8406 | 1.5258 | 0.001526 |

### snapshot_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Take snapshot with 1000 changes | 134.8945 | 0.1349 | 0.000135 |

### text_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTTextHandler do 1000 operations and get value (incremental cache update: true) | 2893.1000 | 2.8931 | 0.002893 |
| CRDTTextHandler do 1000 operations and get value (incremental cache update: false) | 3006.9341 | 3.0069 | 0.003007 |

### topological_sort_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Import 1000 concurrent changes | 1093.6905 | 1.0937 | 0.001094 |

### version_vector_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| VersionVector toBytes 10 peers x1000 | 438.7883 | 0.4388 | 0.000439 |
| VersionVector fromBytes 10 peers x1000 | 664.5896 | 0.6646 | 0.000665 |
| VersionVector intersection 10 peers x1000 | 209.9114 | 0.2099 | 0.000210 |

