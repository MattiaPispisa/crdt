### apply_changes_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Apply 1000 changes | 942.9290 | 0.9429 | 0.000943 |

### apply_changes_capabilities_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Apply 1000 changes (capabilities tracked) | 956.0135 | 0.9560 | 0.000956 |

### change_roundtrip_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Change toBytes x1000 | 61.3907 | 0.0614 | 0.000061 |
| Change fromBytes x1000 | 18.6202 | 0.0186 | 0.000019 |
| Change roundtrip x1000 | 81.3700 | 0.0814 | 0.000081 |

### dag_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| DAG addNode chain of 1000 | 182.6288 | 0.1826 | 0.000183 |
| DAG getAncestors chain of 200 | 7.4550 | 0.0075 | 0.000007 |

### delta_emission_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text remote keystroke + read on 2000 chars (watched: false) | 42.7850 | 0.0428 | 0.000043 |
| Fugue text remote keystroke + read on 2000 chars (watched: true) | 33.9750 | 0.0340 | 0.000034 |
| Fugue text remote keystroke + read on 10000 chars (watched: false) | 88.2000 | 0.0882 | 0.000088 |
| Fugue text remote keystroke + read on 10000 chars (watched: true) | 84.1000 | 0.0841 | 0.000084 |
| Text remote keystroke + read on 2000 chars (watched: false) | 8.9650 | 0.0090 | 0.000009 |
| Text remote keystroke + read on 2000 chars (watched: true) | 12.6250 | 0.0126 | 0.000013 |
| Text remote keystroke + read on 10000 chars (watched: false) | 11.4650 | 0.0115 | 0.000011 |
| Text remote keystroke + read on 10000 chars (watched: true) | 15.7100 | 0.0157 | 0.000016 |
| Map remote write + read on 1000 keys (watched: false) | 7.8400 | 0.0078 | 0.000008 |
| Map remote write + read on 1000 keys (watched: true) | 13.4350 | 0.0134 | 0.000013 |
| Map remote write + read on 5000 keys (watched: false) | 4.4850 | 0.0045 | 0.000004 |
| Map remote write + read on 5000 keys (watched: true) | 5.3500 | 0.0053 | 0.000005 |
| Movable list remote move + read on 1000 elements (watched: false) | 47.3950 | 0.0474 | 0.000047 |
| Movable list remote move + read on 1000 elements (watched: true) | 68.6400 | 0.0686 | 0.000069 |
| Movable list remote move + read on 5000 elements (watched: false) | 181.1800 | 0.1812 | 0.000181 |
| Movable list remote move + read on 5000 elements (watched: true) | 338.3300 | 0.3383 | 0.000338 |
| Fugue text type 2000 chars locally (watched: false) | 55555.9459 | 55.5559 | 0.055556 |
| Fugue text type 2000 chars locally (watched: true) | 84277.7241 | 84.2777 | 0.084278 |

### fugue_list_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTFugueListHandler do 1000 operations and get value (incremental cache update: true) | 3051.6682 | 3.0517 | 0.003052 |

### fugue_snapshot_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text takeSnapshot of 10000 elements (tombstones: false) | 998.7315 | 0.9987 | 0.000999 |
| Fugue text restore of 10000 elements from snapshot (tombstones: false) | 1238.0906 | 1.2381 | 0.001238 |
| Fugue text takeSnapshot of 10000 elements (tombstones: true) | 1079.1602 | 1.0792 | 0.001079 |
| Fugue text restore of 10000 elements from snapshot (tombstones: true) | 1273.9133 | 1.2739 | 0.001274 |
| Fugue text takeSnapshot of 100000 elements (tombstones: false) | 42357.4000 | 42.3574 | 0.042357 |
| Fugue text restore of 100000 elements from snapshot (tombstones: false) | 32776.0000 | 32.7760 | 0.032776 |
| Fugue text takeSnapshot of 100000 elements (tombstones: true) | 43902.9667 | 43.9030 | 0.043903 |
| Fugue text restore of 100000 elements from snapshot (tombstones: true) | 32188.7571 | 32.1888 | 0.032189 |

### fugue_text_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text keystroke + length on 30000 chars | 11.9250 | 0.0119 | 0.000012 |
| Fugue text keystroke + value on 30000 chars | 360.0800 | 0.3601 | 0.000360 |
| Fugue text update on 30000 chars | 1.7250 | 0.0017 | 0.000002 |

### fugue_tree_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| FugueTree append 50000 elements | 10832.1263 | 10.8321 | 0.010832 |
| FugueTree prepend 50000 elements | 92014.1500 | 92.0142 | 0.092014 |
| FugueTree random insert 50000 elements | 116325.3000 | 116.3253 | 0.116325 |
| FugueTree values() over 50000 live elements | 385.8894 | 0.3859 | 0.000386 |
| FugueTree values() over 50000 elements, 90% tombstones | 61.5764 | 0.0616 | 0.000062 |

### list_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTListHandler do 1000 operations and get value (incremental cache update: true) | 2396.9506 | 2.3970 | 0.002397 |

### map_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTMapHandler do 1000 operations and get value (incremental cache update: true) | 2728.3545 | 2.7284 | 0.002728 |

### nested_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Resolve nested tree with 50 leaves (cold caches) | 110.5189 | 0.1105 | 0.000111 |
| Resolve nested tree with 200 leaves (cold caches) | 477.0209 | 0.4770 | 0.000477 |
| Resolve nested tree with 800 leaves (cold caches) | 1995.5728 | 1.9956 | 0.001996 |
| Import + resolve nested tree with 50 leaves (fresh peer) | 171.1165 | 0.1711 | 0.000171 |
| Import + resolve nested tree with 200 leaves (fresh peer) | 646.8390 | 0.6468 | 0.000647 |
| Import + resolve nested tree with 800 leaves (fresh peer) | 3383.5638 | 3.3836 | 0.003384 |

### op_id_key_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| OpIdKey view x100k | 464.3357 | 0.4643 | 0.000464 |
| OpIdKey hashCode x100k (cold) | 1818.5714 | 1.8186 | 0.001819 |
| OpIdKey map lookup x10k | 68.8751 | 0.0689 | 0.000069 |
| OperationId map lookup x10k | 57.5273 | 0.0575 | 0.000058 |

### or_set_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTORSetHandler do 1000 operations and get value (incremental cache update: true) | 2836.9053 | 2.8369 | 0.002837 |

### peer_id_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| PeerId generate x100 | 192.1903 | 0.1922 | 0.000192 |
| PeerId toUint8List x1000 | 32.0119 | 0.0320 | 0.000032 |
| PeerId fromUint8List x1000 | 53.1657 | 0.0532 | 0.000053 |

### remote_apply_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text remote keystroke + read on 2000 chars | 42.9350 | 0.0429 | 0.000043 |
| Fugue text remote keystroke + read on 10000 chars | 93.4250 | 0.0934 | 0.000093 |
| Fugue text remote keystroke + read on 30000 chars | 316.9650 | 0.3170 | 0.000317 |
| Text remote keystroke + read on 2000 chars | 9.6850 | 0.0097 | 0.000010 |
| Text remote keystroke + read on 10000 chars | 12.2950 | 0.0123 | 0.000012 |
| Text remote keystroke + read on 30000 chars | 20.0750 | 0.0201 | 0.000020 |
| Map remote set + read on 1000 keys | 12.0850 | 0.0121 | 0.000012 |
| Map remote set + read on 5000 keys | 11.2250 | 0.0112 | 0.000011 |
| OR-set remote add from the past + read on 1000 values | 40.0100 | 0.0400 | 0.000040 |
| OR-set remote add from the past + read on 5000 values | 103.1200 | 0.1031 | 0.000103 |
| OR-map remote put from the past + read on 1000 keys | 63.2800 | 0.0633 | 0.000063 |
| OR-map remote put from the past + read on 5000 keys | 234.3050 | 0.2343 | 0.000234 |
| Movable list remote move from the past + read on 1000 items | 46.1750 | 0.0462 | 0.000046 |
| Movable list remote move from the past + read on 5000 items | 174.1350 | 0.1741 | 0.000174 |

### scaling_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Import 1000 chained changes | 922.9861 | 0.9230 | 0.000923 |
| Import 10000 chained changes | 11112.1913 | 11.1122 | 0.011112 |
| exportChangesNewerThan on 50000 changes / 10 peers (99% caught-up) | 1.8079 | 0.0018 | 0.000002 |
| takeSnapshot(pruneHistory) with 10000 changes | 21915.3455 | 21.9153 | 0.021915 |
| takeSnapshot(pruneHistory) with 100 concurrent heads | 3563.0596 | 3.5631 | 0.003563 |

### serialization_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Binary encode/decode 1000 changes | 1584.0780 | 1.5841 | 0.001584 |

### snapshot_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Take snapshot with 1000 changes | 135.8471 | 0.1358 | 0.000136 |

### text_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTTextHandler do 1000 operations and get value (incremental cache update: true) | 2937.2562 | 2.9373 | 0.002937 |
| CRDTTextHandler do 1000 operations and get value (incremental cache update: false) | 3049.7854 | 3.0498 | 0.003050 |

### topological_sort_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Import 1000 concurrent changes | 937.7778 | 0.9378 | 0.000938 |

### undo_manager_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text type 300 chars locally (undo managers: 0) | 658.1000 | 0.6581 | 0.000658 |
| Fugue text type 300 chars locally (undo managers: 1) | 796.0000 | 0.7960 | 0.000796 |
| Fugue text type 300 chars locally (undo managers: 2) | 864.1333 | 0.8641 | 0.000864 |
| Fugue text type 300 chars locally (undo managers: 3) | 876.6000 | 0.8766 | 0.000877 |
| Fugue text type 300 chars locally (undo managers: 5) | 905.8000 | 0.9058 | 0.000906 |
| Fugue text undo+redo one keystroke on 2000 chars | 6.1500 | 0.0062 | 0.000006 |
| Fugue text undo+redo one keystroke on 10000 chars | 4.5500 | 0.0046 | 0.000005 |
| Fugue text undo+redo a 1-char delete on 5000 chars | 4.5000 | 0.0045 | 0.000005 |
| Fugue text undo+redo a 100-char delete on 5000 chars | 57.0500 | 0.0570 | 0.000057 |
| Fugue text undo+redo a 500-char delete on 5000 chars | 362.7500 | 0.3628 | 0.000363 |
| Map undo+redo one set on 5000 keys | 3.7500 | 0.0037 | 0.000004 |
| OR-set undo+redo one add on 5000 values | 4.6000 | 0.0046 | 0.000005 |
| Fugue text undo/redo ping-pong x10 on 2000 chars | 477.6667 | 0.4777 | 0.000478 |
| Fugue text undo/redo ping-pong x100 on 2000 chars | 1333.0000 | 1.3330 | 0.001333 |
| Fugue text undo/redo ping-pong x1000 on 2000 chars | 12569.3333 | 12.5693 | 0.012569 |

### version_vector_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| VersionVector toBytes 10 peers x1000 | 439.0380 | 0.4390 | 0.000439 |
| VersionVector fromBytes 10 peers x1000 | 672.1857 | 0.6722 | 0.000672 |
| VersionVector intersection 10 peers x1000 | 210.6691 | 0.2107 | 0.000211 |

