### apply_changes_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Apply 1000 changes | 1079.4700 | 1.0795 | 0.001079 |

### apply_changes_capabilities_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Apply 1000 changes (capabilities tracked) | 994.0426 | 0.9940 | 0.000994 |

### change_roundtrip_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Change toBytes x1000 | 62.8546 | 0.0629 | 0.000063 |
| Change fromBytes x1000 | 18.7267 | 0.0187 | 0.000019 |
| Change roundtrip x1000 | 83.0559 | 0.0831 | 0.000083 |

### dag_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| DAG addNode chain of 1000 | 186.8041 | 0.1868 | 0.000187 |
| DAG getAncestors chain of 200 | 7.5958 | 0.0076 | 0.000008 |

### delta_emission_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text remote keystroke + read on 2000 chars (watched: false) | 44.9850 | 0.0450 | 0.000045 |
| Fugue text remote keystroke + read on 2000 chars (watched: true) | 36.1650 | 0.0362 | 0.000036 |
| Fugue text remote keystroke + read on 10000 chars (watched: false) | 88.7100 | 0.0887 | 0.000089 |
| Fugue text remote keystroke + read on 10000 chars (watched: true) | 85.2450 | 0.0852 | 0.000085 |
| Text remote keystroke + read on 2000 chars (watched: false) | 9.1750 | 0.0092 | 0.000009 |
| Text remote keystroke + read on 2000 chars (watched: true) | 12.1000 | 0.0121 | 0.000012 |
| Text remote keystroke + read on 10000 chars (watched: false) | 10.5950 | 0.0106 | 0.000011 |
| Text remote keystroke + read on 10000 chars (watched: true) | 15.9050 | 0.0159 | 0.000016 |
| Map remote write + read on 1000 keys (watched: false) | 8.4550 | 0.0085 | 0.000008 |
| Map remote write + read on 1000 keys (watched: true) | 9.8350 | 0.0098 | 0.000010 |
| Map remote write + read on 5000 keys (watched: false) | 4.8850 | 0.0049 | 0.000005 |
| Map remote write + read on 5000 keys (watched: true) | 6.2500 | 0.0063 | 0.000006 |
| Movable list remote move + read on 1000 elements (watched: false) | 45.8550 | 0.0459 | 0.000046 |
| Movable list remote move + read on 1000 elements (watched: true) | 75.1850 | 0.0752 | 0.000075 |
| Movable list remote move + read on 5000 elements (watched: false) | 186.0700 | 0.1861 | 0.000186 |
| Movable list remote move + read on 5000 elements (watched: true) | 347.2300 | 0.3472 | 0.000347 |
| Fugue text type 2000 chars locally (watched: false) | 57069.1111 | 57.0691 | 0.057069 |
| Fugue text type 2000 chars locally (watched: true) | 92038.3929 | 92.0384 | 0.092038 |

### fugue_list_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTFugueListHandler do 1000 operations and get value (incremental cache update: true) | 3136.6397 | 3.1366 | 0.003137 |

### fugue_snapshot_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text takeSnapshot of 10000 elements (tombstones: false) | 1057.2079 | 1.0572 | 0.001057 |
| Fugue text restore of 10000 elements from snapshot (tombstones: false) | 1142.6395 | 1.1426 | 0.001143 |
| Fugue text takeSnapshot of 10000 elements (tombstones: true) | 1132.6033 | 1.1326 | 0.001133 |
| Fugue text restore of 10000 elements from snapshot (tombstones: true) | 1355.5021 | 1.3555 | 0.001356 |
| Fugue text takeSnapshot of 100000 elements (tombstones: false) | 37758.8818 | 37.7589 | 0.037759 |
| Fugue text restore of 100000 elements from snapshot (tombstones: false) | 21154.6500 | 21.1547 | 0.021155 |
| Fugue text takeSnapshot of 100000 elements (tombstones: true) | 42491.5778 | 42.4916 | 0.042492 |
| Fugue text restore of 100000 elements from snapshot (tombstones: true) | 27802.1400 | 27.8021 | 0.027802 |

### fugue_text_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text keystroke + length on 30000 chars | 13.2800 | 0.0133 | 0.000013 |
| Fugue text keystroke + value on 30000 chars | 357.3400 | 0.3573 | 0.000357 |
| Fugue text update on 30000 chars | 1.7350 | 0.0017 | 0.000002 |

### fugue_tree_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| FugueTree append 50000 elements | 10973.4474 | 10.9734 | 0.010973 |
| FugueTree prepend 50000 elements | 93993.5500 | 93.9935 | 0.093994 |
| FugueTree random insert 50000 elements | 118734.6500 | 118.7346 | 0.118735 |
| FugueTree values() over 50000 live elements | 376.2848 | 0.3763 | 0.000376 |
| FugueTree values() over 50000 elements, 90% tombstones | 62.7273 | 0.0627 | 0.000063 |

### hlc_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| HLC toUint8List x100k | 25.1833 | 0.0252 | 0.000025 |
| HLC fromUint8List x100k | 498.8837 | 0.4989 | 0.000499 |
| HLC compareTo x100k | 45.9227 | 0.0459 | 0.000046 |

### list_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTListHandler do 1000 operations and get value (incremental cache update: true) | 2508.9767 | 2.5090 | 0.002509 |

### map_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTMapHandler do 1000 operations and get value (incremental cache update: true) | 2435.9202 | 2.4359 | 0.002436 |

### nested_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Resolve nested tree with 50 leaves (cold caches) | 110.9641 | 0.1110 | 0.000111 |
| Resolve nested tree with 200 leaves (cold caches) | 477.2144 | 0.4772 | 0.000477 |
| Resolve nested tree with 800 leaves (cold caches) | 2008.3160 | 2.0083 | 0.002008 |
| Import + resolve nested tree with 50 leaves (fresh peer) | 386.1575 | 0.3862 | 0.000386 |
| Import + resolve nested tree with 200 leaves (fresh peer) | 1501.0758 | 1.5011 | 0.001501 |
| Import + resolve nested tree with 800 leaves (fresh peer) | 7503.8744 | 7.5039 | 0.007504 |

### op_id_key_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| OpIdKey view x100k | 474.4272 | 0.4744 | 0.000474 |
| OpIdKey hashCode x100k (cold) | 1836.0116 | 1.8360 | 0.001836 |
| OpIdKey map lookup x10k | 64.1378 | 0.0641 | 0.000064 |
| OperationId map lookup x10k | 61.2321 | 0.0612 | 0.000061 |

### or_set_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTORSetHandler do 1000 operations and get value (incremental cache update: true) | 2812.9465 | 2.8129 | 0.002813 |

### peer_id_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| PeerId generate x100 | 162.3251 | 0.1623 | 0.000162 |
| PeerId toUint8List x1000 | 32.0184 | 0.0320 | 0.000032 |
| PeerId fromUint8List x1000 | 54.0535 | 0.0541 | 0.000054 |

### remote_apply_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text remote keystroke + read on 2000 chars | 43.2700 | 0.0433 | 0.000043 |
| Fugue text remote keystroke + read on 10000 chars | 92.1000 | 0.0921 | 0.000092 |
| Fugue text remote keystroke + read on 30000 chars | 318.7050 | 0.3187 | 0.000319 |
| Text remote keystroke + read on 2000 chars | 9.7150 | 0.0097 | 0.000010 |
| Text remote keystroke + read on 10000 chars | 12.2300 | 0.0122 | 0.000012 |
| Text remote keystroke + read on 30000 chars | 18.9650 | 0.0190 | 0.000019 |
| Map remote set + read on 1000 keys | 10.2100 | 0.0102 | 0.000010 |
| Map remote set + read on 5000 keys | 5.0350 | 0.0050 | 0.000005 |
| OR-set remote add from the past + read on 1000 values | 34.3400 | 0.0343 | 0.000034 |
| OR-set remote add from the past + read on 5000 values | 104.3000 | 0.1043 | 0.000104 |
| OR-map remote put from the past + read on 1000 keys | 61.5800 | 0.0616 | 0.000062 |
| OR-map remote put from the past + read on 5000 keys | 236.3600 | 0.2364 | 0.000236 |
| Movable list remote move from the past + read on 1000 items | 49.8500 | 0.0498 | 0.000050 |
| Movable list remote move from the past + read on 5000 items | 178.4500 | 0.1784 | 0.000178 |

### scaling_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Import 1000 chained changes | 928.6139 | 0.9286 | 0.000929 |
| Import 10000 chained changes | 11151.6167 | 11.1516 | 0.011152 |
| exportChangesNewerThan on 50000 changes / 10 peers (99% caught-up) | 2.0129 | 0.0020 | 0.000002 |
| takeSnapshot(pruneHistory) with 10000 changes | 22577.3111 | 22.5773 | 0.022577 |
| takeSnapshot(pruneHistory) with 100 concurrent heads | 4073.3220 | 4.0733 | 0.004073 |

### serialization_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Binary encode/decode 1000 changes | 1548.8440 | 1.5488 | 0.001549 |

### snapshot_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Take snapshot with 1000 changes | 132.9742 | 0.1330 | 0.000133 |

### text_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTTextHandler do 1000 operations and get value (incremental cache update: true) | 2936.9671 | 2.9370 | 0.002937 |
| CRDTTextHandler do 1000 operations and get value (incremental cache update: false) | 3084.6137 | 3.0846 | 0.003085 |

### topological_sort_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Import 1000 concurrent changes | 932.4526 | 0.9325 | 0.000932 |

### undo_manager_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text type 300 chars locally (undo managers: 0) | 736.8000 | 0.7368 | 0.000737 |
| Fugue text type 300 chars locally (undo managers: 1) | 858.8333 | 0.8588 | 0.000859 |
| Fugue text type 300 chars locally (undo managers: 2) | 871.0667 | 0.8711 | 0.000871 |
| Fugue text type 300 chars locally (undo managers: 3) | 861.9000 | 0.8619 | 0.000862 |
| Fugue text type 300 chars locally (undo managers: 5) | 908.9667 | 0.9090 | 0.000909 |
| Fugue text undo+redo one keystroke on 2000 chars | 4.5000 | 0.0045 | 0.000005 |
| Fugue text undo+redo one keystroke on 10000 chars | 4.5500 | 0.0046 | 0.000005 |
| Fugue text undo+redo a 1-char delete on 5000 chars | 12.7500 | 0.0127 | 0.000013 |
| Fugue text undo+redo a 100-char delete on 5000 chars | 56.4500 | 0.0565 | 0.000056 |
| Fugue text undo+redo a 500-char delete on 5000 chars | 358.4500 | 0.3584 | 0.000358 |
| Map undo+redo one set on 5000 keys | 3.8500 | 0.0039 | 0.000004 |
| OR-set undo+redo one add on 5000 values | 4.6500 | 0.0047 | 0.000005 |
| Fugue text undo/redo ping-pong x10 on 2000 chars | 481.6667 | 0.4817 | 0.000482 |
| Fugue text undo/redo ping-pong x100 on 2000 chars | 1624.0000 | 1.6240 | 0.001624 |
| Fugue text undo/redo ping-pong x1000 on 2000 chars | 12281.3333 | 12.2813 | 0.012281 |

### version_vector_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| VersionVector toBytes 10 peers x1000 | 463.7518 | 0.4638 | 0.000464 |
| VersionVector fromBytes 10 peers x1000 | 683.5023 | 0.6835 | 0.000684 |
| VersionVector intersection 10 peers x1000 | 212.3910 | 0.2124 | 0.000212 |

