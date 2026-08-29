### apply_changes_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Apply 1000 changes | 933.8894 | 0.9339 | 0.000934 |

### change_roundtrip_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Change toBytes x1000 | 62.0515 | 0.0621 | 0.000062 |
| Change fromBytes x1000 | 18.6861 | 0.0187 | 0.000019 |
| Change roundtrip x1000 | 81.6776 | 0.0817 | 0.000082 |

### dag_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| DAG addNode chain of 1000 | 186.4018 | 0.1864 | 0.000186 |
| DAG getAncestors chain of 200 | 7.6813 | 0.0077 | 0.000008 |

### delta_emission_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text remote keystroke + read on 2000 chars (watched: false) | 42.2150 | 0.0422 | 0.000042 |
| Fugue text remote keystroke + read on 2000 chars (watched: true) | 33.6850 | 0.0337 | 0.000034 |
| Fugue text remote keystroke + read on 10000 chars (watched: false) | 87.5950 | 0.0876 | 0.000088 |
| Fugue text remote keystroke + read on 10000 chars (watched: true) | 84.4500 | 0.0844 | 0.000084 |
| Text remote keystroke + read on 2000 chars (watched: false) | 9.1800 | 0.0092 | 0.000009 |
| Text remote keystroke + read on 2000 chars (watched: true) | 12.3250 | 0.0123 | 0.000012 |
| Text remote keystroke + read on 10000 chars (watched: false) | 12.3350 | 0.0123 | 0.000012 |
| Text remote keystroke + read on 10000 chars (watched: true) | 17.7350 | 0.0177 | 0.000018 |
| Map remote write + read on 1000 keys (watched: false) | 8.4350 | 0.0084 | 0.000008 |
| Map remote write + read on 1000 keys (watched: true) | 9.0650 | 0.0091 | 0.000009 |
| Map remote write + read on 5000 keys (watched: false) | 5.0650 | 0.0051 | 0.000005 |
| Map remote write + read on 5000 keys (watched: true) | 5.1150 | 0.0051 | 0.000005 |
| Movable list remote move + read on 1000 elements (watched: false) | 52.8350 | 0.0528 | 0.000053 |
| Movable list remote move + read on 1000 elements (watched: true) | 77.8950 | 0.0779 | 0.000078 |
| Movable list remote move + read on 5000 elements (watched: false) | 191.5950 | 0.1916 | 0.000192 |
| Movable list remote move + read on 5000 elements (watched: true) | 366.7000 | 0.3667 | 0.000367 |
| Fugue text type 2000 chars locally (watched: false) | 56341.2703 | 56.3413 | 0.056341 |
| Fugue text type 2000 chars locally (watched: true) | 73365.2973 | 73.3653 | 0.073365 |

### fugue_list_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTFugueListHandler do 1000 operations and get value (incremental cache update: true) | 3012.7750 | 3.0128 | 0.003013 |

### fugue_snapshot_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text takeSnapshot of 10000 elements (tombstones: false) | 1031.1810 | 1.0312 | 0.001031 |
| Fugue text restore of 10000 elements from snapshot (tombstones: false) | 1133.2337 | 1.1332 | 0.001133 |
| Fugue text takeSnapshot of 10000 elements (tombstones: true) | 1094.3827 | 1.0944 | 0.001094 |
| Fugue text restore of 10000 elements from snapshot (tombstones: true) | 1224.2802 | 1.2243 | 0.001224 |
| Fugue text takeSnapshot of 100000 elements (tombstones: false) | 28714.7111 | 28.7147 | 0.028715 |
| Fugue text restore of 100000 elements from snapshot (tombstones: false) | 22628.5563 | 22.6286 | 0.022629 |
| Fugue text takeSnapshot of 100000 elements (tombstones: true) | 42522.3000 | 42.5223 | 0.042522 |
| Fugue text restore of 100000 elements from snapshot (tombstones: true) | 21993.5125 | 21.9935 | 0.021994 |

### fugue_text_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text keystroke + length on 30000 chars | 12.3650 | 0.0124 | 0.000012 |
| Fugue text keystroke + value on 30000 chars | 347.5050 | 0.3475 | 0.000348 |
| Fugue text update on 30000 chars | 1.6600 | 0.0017 | 0.000002 |

### fugue_tree_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| FugueTree append 50000 elements | 10914.1053 | 10.9141 | 0.010914 |
| FugueTree prepend 50000 elements | 92987.2000 | 92.9872 | 0.092987 |
| FugueTree random insert 50000 elements | 117900.8500 | 117.9009 | 0.117901 |
| FugueTree values() over 50000 live elements | 377.2288 | 0.3772 | 0.000377 |
| FugueTree values() over 50000 elements, 90% tombstones | 61.8458 | 0.0618 | 0.000062 |

### hlc_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| HLC toUint8List x100k | 24.5449 | 0.0245 | 0.000025 |
| HLC fromUint8List x100k | 502.4877 | 0.5025 | 0.000502 |
| HLC compareTo x100k | 45.5777 | 0.0456 | 0.000046 |

### list_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTListHandler do 1000 operations and get value (incremental cache update: true) | 2361.0500 | 2.3611 | 0.002361 |

### map_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTMapHandler do 1000 operations and get value (incremental cache update: true) | 2388.7570 | 2.3888 | 0.002389 |

### nested_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Resolve nested tree with 50 leaves (cold caches) | 108.4828 | 0.1085 | 0.000108 |
| Resolve nested tree with 200 leaves (cold caches) | 463.6353 | 0.4636 | 0.000464 |
| Resolve nested tree with 800 leaves (cold caches) | 1954.8039 | 1.9548 | 0.001955 |
| Import + resolve nested tree with 50 leaves (fresh peer) | 371.7843 | 0.3718 | 0.000372 |
| Import + resolve nested tree with 200 leaves (fresh peer) | 1535.9435 | 1.5359 | 0.001536 |
| Import + resolve nested tree with 800 leaves (fresh peer) | 6063.9238 | 6.0639 | 0.006064 |

### op_id_key_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| OpIdKey view x100k | 473.5000 | 0.4735 | 0.000474 |
| OpIdKey hashCode x100k (cold) | 1824.8125 | 1.8248 | 0.001825 |
| OpIdKey map lookup x10k | 67.8225 | 0.0678 | 0.000068 |
| OperationId map lookup x10k | 61.3024 | 0.0613 | 0.000061 |

### or_set_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTORSetHandler do 1000 operations and get value (incremental cache update: true) | 2653.3592 | 2.6534 | 0.002653 |

### peer_id_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| PeerId generate x100 | 162.3013 | 0.1623 | 0.000162 |
| PeerId toUint8List x1000 | 31.8005 | 0.0318 | 0.000032 |
| PeerId fromUint8List x1000 | 53.9061 | 0.0539 | 0.000054 |

### remote_apply_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text remote keystroke + read on 2000 chars | 42.2400 | 0.0422 | 0.000042 |
| Fugue text remote keystroke + read on 10000 chars | 92.6500 | 0.0927 | 0.000093 |
| Fugue text remote keystroke + read on 30000 chars | 320.9800 | 0.3210 | 0.000321 |
| Text remote keystroke + read on 2000 chars | 9.8200 | 0.0098 | 0.000010 |
| Text remote keystroke + read on 10000 chars | 12.9400 | 0.0129 | 0.000013 |
| Text remote keystroke + read on 30000 chars | 20.4050 | 0.0204 | 0.000020 |
| Map remote set + read on 1000 keys | 8.3800 | 0.0084 | 0.000008 |
| Map remote set + read on 5000 keys | 5.2800 | 0.0053 | 0.000005 |
| OR-set remote add from the past + read on 1000 values | 36.7800 | 0.0368 | 0.000037 |
| OR-set remote add from the past + read on 5000 values | 90.3700 | 0.0904 | 0.000090 |
| OR-map remote put from the past + read on 1000 keys | 63.5400 | 0.0635 | 0.000064 |
| OR-map remote put from the past + read on 5000 keys | 249.7250 | 0.2497 | 0.000250 |
| Movable list remote move from the past + read on 1000 items | 51.0250 | 0.0510 | 0.000051 |
| Movable list remote move from the past + read on 5000 items | 182.1800 | 0.1822 | 0.000182 |

### scaling_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Import 1000 chained changes | 909.4960 | 0.9095 | 0.000909 |
| Import 10000 chained changes | 10801.2100 | 10.8012 | 0.010801 |
| exportChangesNewerThan on 50000 changes / 10 peers (99% caught-up) | 3.2873 | 0.0033 | 0.000003 |
| takeSnapshot(pruneHistory) with 10000 changes | 22263.2500 | 22.2632 | 0.022263 |
| takeSnapshot(pruneHistory) with 100 concurrent heads | 3852.5462 | 3.8525 | 0.003853 |

### serialization_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Binary encode/decode 1000 changes | 1522.3752 | 1.5224 | 0.001522 |

### snapshot_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Take snapshot with 1000 changes | 132.4952 | 0.1325 | 0.000132 |

### text_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTTextHandler do 1000 operations and get value (incremental cache update: true) | 2917.8655 | 2.9179 | 0.002918 |
| CRDTTextHandler do 1000 operations and get value (incremental cache update: false) | 3079.5210 | 3.0795 | 0.003080 |

### topological_sort_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Import 1000 concurrent changes | 931.1903 | 0.9312 | 0.000931 |

### version_vector_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| VersionVector toBytes 10 peers x1000 | 448.0894 | 0.4481 | 0.000448 |
| VersionVector fromBytes 10 peers x1000 | 654.4383 | 0.6544 | 0.000654 |
| VersionVector intersection 10 peers x1000 | 199.9234 | 0.1999 | 0.000200 |

