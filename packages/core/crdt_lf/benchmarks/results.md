### apply_changes_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Apply 1000 changes | 920.9422 | 0.9209 | 0.000921 |

### apply_changes_capabilities_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Apply 1000 changes (capabilities tracked) | 963.6246 | 0.9636 | 0.000964 |

### change_roundtrip_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Change toBytes x1000 | 61.7876 | 0.0618 | 0.000062 |
| Change fromBytes x1000 | 18.7318 | 0.0187 | 0.000019 |
| Change roundtrip x1000 | 81.7818 | 0.0818 | 0.000082 |

### dag_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| DAG addNode chain of 1000 | 185.5043 | 0.1855 | 0.000186 |
| DAG getAncestors chain of 200 | 7.6318 | 0.0076 | 0.000008 |

### delta_emission_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text remote keystroke + read on 2000 chars (watched: false) | 42.3300 | 0.0423 | 0.000042 |
| Fugue text remote keystroke + read on 2000 chars (watched: true) | 36.1500 | 0.0362 | 0.000036 |
| Fugue text remote keystroke + read on 10000 chars (watched: false) | 88.3400 | 0.0883 | 0.000088 |
| Fugue text remote keystroke + read on 10000 chars (watched: true) | 84.5850 | 0.0846 | 0.000085 |
| Text remote keystroke + read on 2000 chars (watched: false) | 8.9450 | 0.0089 | 0.000009 |
| Text remote keystroke + read on 2000 chars (watched: true) | 15.8100 | 0.0158 | 0.000016 |
| Text remote keystroke + read on 10000 chars (watched: false) | 11.2500 | 0.0112 | 0.000011 |
| Text remote keystroke + read on 10000 chars (watched: true) | 18.4400 | 0.0184 | 0.000018 |
| Map remote write + read on 1000 keys (watched: false) | 7.2600 | 0.0073 | 0.000007 |
| Map remote write + read on 1000 keys (watched: true) | 10.0550 | 0.0101 | 0.000010 |
| Map remote write + read on 5000 keys (watched: false) | 4.0750 | 0.0041 | 0.000004 |
| Map remote write + read on 5000 keys (watched: true) | 5.0250 | 0.0050 | 0.000005 |
| Movable list remote move + read on 1000 elements (watched: false) | 45.3550 | 0.0454 | 0.000045 |
| Movable list remote move + read on 1000 elements (watched: true) | 70.8000 | 0.0708 | 0.000071 |
| Movable list remote move + read on 5000 elements (watched: false) | 185.0500 | 0.1851 | 0.000185 |
| Movable list remote move + read on 5000 elements (watched: true) | 344.7000 | 0.3447 | 0.000345 |
| Fugue text type 2000 chars locally (watched: false) | 56826.5000 | 56.8265 | 0.056827 |
| Fugue text type 2000 chars locally (watched: true) | 79695.2143 | 79.6952 | 0.079695 |

### fugue_list_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTFugueListHandler do 1000 operations and get value (incremental cache update: true) | 3126.8754 | 3.1269 | 0.003127 |

### fugue_snapshot_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text takeSnapshot of 10000 elements (tombstones: false) | 1015.1660 | 1.0152 | 0.001015 |
| Fugue text restore of 10000 elements from snapshot (tombstones: false) | 1198.1944 | 1.1982 | 0.001198 |
| Fugue text takeSnapshot of 10000 elements (tombstones: true) | 1113.5978 | 1.1136 | 0.001114 |
| Fugue text restore of 10000 elements from snapshot (tombstones: true) | 1105.5360 | 1.1055 | 0.001106 |
| Fugue text takeSnapshot of 100000 elements (tombstones: false) | 30657.7273 | 30.6577 | 0.030658 |
| Fugue text restore of 100000 elements from snapshot (tombstones: false) | 25268.2867 | 25.2683 | 0.025268 |
| Fugue text takeSnapshot of 100000 elements (tombstones: true) | 47462.6778 | 47.4627 | 0.047463 |
| Fugue text restore of 100000 elements from snapshot (tombstones: true) | 13286.1250 | 13.2861 | 0.013286 |

### fugue_text_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text keystroke + length on 30000 chars | 13.0300 | 0.0130 | 0.000013 |
| Fugue text keystroke + value on 30000 chars | 330.6000 | 0.3306 | 0.000331 |
| Fugue text update on 30000 chars | 1.7300 | 0.0017 | 0.000002 |

### fugue_tree_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| FugueTree append 50000 elements | 11230.5389 | 11.2305 | 0.011231 |
| FugueTree prepend 50000 elements | 92095.6000 | 92.0956 | 0.092096 |
| FugueTree random insert 50000 elements | 117755.6000 | 117.7556 | 0.117756 |
| FugueTree values() over 50000 live elements | 369.7668 | 0.3698 | 0.000370 |
| FugueTree values() over 50000 elements, 90% tombstones | 61.9730 | 0.0620 | 0.000062 |

### hlc_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| HLC toUint8List x100k | 24.8925 | 0.0249 | 0.000025 |
| HLC fromUint8List x100k | 501.2210 | 0.5012 | 0.000501 |
| HLC compareTo x100k | 45.0238 | 0.0450 | 0.000045 |

### list_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTListHandler do 1000 operations and get value (incremental cache update: true) | 2371.9886 | 2.3720 | 0.002372 |

### map_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTMapHandler do 1000 operations and get value (incremental cache update: true) | 2489.4875 | 2.4895 | 0.002489 |

### nested_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Resolve nested tree with 50 leaves (cold caches) | 110.7712 | 0.1108 | 0.000111 |
| Resolve nested tree with 200 leaves (cold caches) | 470.4189 | 0.4704 | 0.000470 |
| Resolve nested tree with 800 leaves (cold caches) | 2099.9090 | 2.0999 | 0.002100 |
| Import + resolve nested tree with 50 leaves (fresh peer) | 159.3758 | 0.1594 | 0.000159 |
| Import + resolve nested tree with 200 leaves (fresh peer) | 634.2613 | 0.6343 | 0.000634 |
| Import + resolve nested tree with 800 leaves (fresh peer) | 2645.1670 | 2.6452 | 0.002645 |

### op_id_key_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| OpIdKey view x100k | 473.2371 | 0.4732 | 0.000473 |
| OpIdKey hashCode x100k (cold) | 1866.3089 | 1.8663 | 0.001866 |
| OpIdKey map lookup x10k | 66.2360 | 0.0662 | 0.000066 |
| OperationId map lookup x10k | 61.7955 | 0.0618 | 0.000062 |

### or_set_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTORSetHandler do 1000 operations and get value (incremental cache update: true) | 2834.7761 | 2.8348 | 0.002835 |

### peer_id_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| PeerId generate x100 | 162.7423 | 0.1627 | 0.000163 |
| PeerId toUint8List x1000 | 31.9313 | 0.0319 | 0.000032 |
| PeerId fromUint8List x1000 | 53.2487 | 0.0532 | 0.000053 |

### remote_apply_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text remote keystroke + read on 2000 chars | 43.2650 | 0.0433 | 0.000043 |
| Fugue text remote keystroke + read on 10000 chars | 92.1750 | 0.0922 | 0.000092 |
| Fugue text remote keystroke + read on 30000 chars | 318.6550 | 0.3187 | 0.000319 |
| Text remote keystroke + read on 2000 chars | 10.1400 | 0.0101 | 0.000010 |
| Text remote keystroke + read on 10000 chars | 13.1300 | 0.0131 | 0.000013 |
| Text remote keystroke + read on 30000 chars | 21.0900 | 0.0211 | 0.000021 |
| Map remote set + read on 1000 keys | 10.0850 | 0.0101 | 0.000010 |
| Map remote set + read on 5000 keys | 4.7950 | 0.0048 | 0.000005 |
| OR-set remote add from the past + read on 1000 values | 35.2700 | 0.0353 | 0.000035 |
| OR-set remote add from the past + read on 5000 values | 106.2800 | 0.1063 | 0.000106 |
| OR-map remote put from the past + read on 1000 keys | 60.3600 | 0.0604 | 0.000060 |
| OR-map remote put from the past + read on 5000 keys | 230.3250 | 0.2303 | 0.000230 |
| Movable list remote move from the past + read on 1000 items | 54.5400 | 0.0545 | 0.000055 |
| Movable list remote move from the past + read on 5000 items | 180.8450 | 0.1808 | 0.000181 |

### scaling_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Import 1000 chained changes | 906.0997 | 0.9061 | 0.000906 |
| Import 10000 chained changes | 12335.6682 | 12.3357 | 0.012336 |
| exportChangesNewerThan on 50000 changes / 10 peers (99% caught-up) | 1.9767 | 0.0020 | 0.000002 |
| takeSnapshot(pruneHistory) with 10000 changes | 20316.7182 | 20.3167 | 0.020317 |
| takeSnapshot(pruneHistory) with 100 concurrent heads | 3601.6375 | 3.6016 | 0.003602 |

### serialization_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Binary encode/decode 1000 changes | 1581.6833 | 1.5817 | 0.001582 |

### snapshot_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Take snapshot with 1000 changes | 132.8658 | 0.1329 | 0.000133 |

### text_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTTextHandler do 1000 operations and get value (incremental cache update: true) | 2900.6453 | 2.9006 | 0.002901 |
| CRDTTextHandler do 1000 operations and get value (incremental cache update: false) | 3138.1286 | 3.1381 | 0.003138 |

### topological_sort_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Import 1000 concurrent changes | 911.9294 | 0.9119 | 0.000912 |

### undo_manager_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text type 300 chars locally (undo managers: 0) | 679.7000 | 0.6797 | 0.000680 |
| Fugue text type 300 chars locally (undo managers: 1) | 843.8000 | 0.8438 | 0.000844 |
| Fugue text type 300 chars locally (undo managers: 2) | 860.6333 | 0.8606 | 0.000861 |
| Fugue text type 300 chars locally (undo managers: 3) | 869.2000 | 0.8692 | 0.000869 |
| Fugue text type 300 chars locally (undo managers: 5) | 899.0667 | 0.8991 | 0.000899 |
| Fugue text undo+redo one keystroke on 2000 chars | 4.6000 | 0.0046 | 0.000005 |
| Fugue text undo+redo one keystroke on 10000 chars | 4.5000 | 0.0045 | 0.000005 |
| Fugue text undo+redo a 1-char delete on 5000 chars | 4.4500 | 0.0044 | 0.000004 |
| Fugue text undo+redo a 100-char delete on 5000 chars | 56.7500 | 0.0568 | 0.000057 |
| Fugue text undo+redo a 500-char delete on 5000 chars | 343.4000 | 0.3434 | 0.000343 |
| Map undo+redo one set on 5000 keys | 3.7000 | 0.0037 | 0.000004 |
| OR-set undo+redo one add on 5000 values | 4.8000 | 0.0048 | 0.000005 |
| Fugue text undo/redo ping-pong x10 on 2000 chars | 481.3333 | 0.4813 | 0.000481 |
| Fugue text undo/redo ping-pong x100 on 2000 chars | 1343.3333 | 1.3433 | 0.001343 |
| Fugue text undo/redo ping-pong x1000 on 2000 chars | 12875.6667 | 12.8757 | 0.012876 |

### version_vector_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| VersionVector toBytes 10 peers x1000 | 444.7228 | 0.4447 | 0.000445 |
| VersionVector fromBytes 10 peers x1000 | 644.4278 | 0.6444 | 0.000644 |
| VersionVector intersection 10 peers x1000 | 202.1794 | 0.2022 | 0.000202 |

