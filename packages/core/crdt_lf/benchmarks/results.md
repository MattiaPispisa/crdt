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

### delete_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Remote delete with 100 open containers | 6.9750 | 0.0070 | 0.000007 |
| Remote delete with 1000 open containers | 5.7300 | 0.0057 | 0.000006 |
| Remote delete with 10000 open containers | 5.1350 | 0.0051 | 0.000005 |
| Remote delete after 100 deletes | 7.6900 | 0.0077 | 0.000008 |
| Remote delete after 1000 deletes | 36.3350 | 0.0363 | 0.000036 |
| Remote delete after 10000 deletes | 327.5300 | 0.3275 | 0.000328 |

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

### rich_text_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text (baseline) keystroke + length on 30000 chars | 13.5650 | 0.0136 | 0.000014 |
| Fugue text (baseline) keystroke + value on 30000 chars | 348.4050 | 0.3484 | 0.000348 |
| Fugue text (baseline) delete + length on 30000 chars | 1.5000 | 0.0015 | 0.000002 |
| Fugue text (baseline) delete + value on 30000 chars | 298.0100 | 0.2980 | 0.000298 |
| Rich text keystroke + length on 30000 chars | 9.9350 | 0.0099 | 0.000010 |
| Rich text keystroke + value on 30000 chars | 364.1250 | 0.3641 | 0.000364 |
| Rich text delete + length on 30000 chars | 1.6900 | 0.0017 | 0.000002 |
| Rich text delete + value on 30000 chars | 325.4650 | 0.3255 | 0.000325 |
| Rich text (marked lines) keystroke + length on 30000 chars | 28.3300 | 0.0283 | 0.000028 |
| Rich text (marked lines) keystroke + value on 30000 chars | 537.2100 | 0.5372 | 0.000537 |
| Rich text (marked lines) delete + length on 30000 chars | 13.9550 | 0.0140 | 0.000014 |
| Rich text (marked lines) delete + value on 30000 chars | 392.7950 | 0.3928 | 0.000393 |
| Fugue text (baseline) insert 100 lines (watched: false) | 931.1000 | 0.9311 | 0.000931 |
| Rich text insert 100 lines (watched: false) | 679.8000 | 0.6798 | 0.000680 |
| Rich text insert 100 lines x 3 attributes (watched: false) | 2171.1000 | 2.1711 | 0.002171 |
| Fugue text (baseline) insert 100 lines (watched: true) | 678.3000 | 0.6783 | 0.000678 |
| Rich text insert 100 lines (watched: true) | 678.7000 | 0.6787 | 0.000679 |
| Rich text insert 100 lines x 3 attributes (watched: true) | 3126.4000 | 3.1264 | 0.003126 |
| Fugue text (baseline) insert 1000 lines (watched: false) | 9673.5000 | 9.6735 | 0.009673 |
| Rich text insert 1000 lines (watched: false) | 10282.8000 | 10.2828 | 0.010283 |
| Rich text insert 1000 lines x 3 attributes (watched: false) | 25169.2000 | 25.1692 | 0.025169 |
| Fugue text (baseline) insert 1000 lines (watched: true) | 10084.2000 | 10.0842 | 0.010084 |
| Rich text insert 1000 lines (watched: true) | 10285.0000 | 10.2850 | 0.010285 |
| Rich text insert 1000 lines x 3 attributes (watched: true) | 71979.9000 | 71.9799 | 0.071980 |
| Rich text format bold on/off + length on 30000 chars (watched: false) | 5.5800 | 0.0056 | 0.000006 |
| Rich text format bold on/off + length on 30000 chars (watched: true) | 6.9800 | 0.0070 | 0.000007 |
| Rich text (marked lines) format bold on/off + length on 30000 chars (watched: false) | 443.7100 | 0.4437 | 0.000444 |
| Rich text (marked lines) format bold on/off + length on 30000 chars (watched: true) | 649.0200 | 0.6490 | 0.000649 |
| Fugue text (baseline) import 1000 line inserts + value | 11959.9000 | 11.9599 | 0.011960 |
| Rich text import 1000 line inserts + value | 11855.4000 | 11.8554 | 0.011855 |
| Rich text (marked lines) import 1000 line inserts + value | 28666.8000 | 28.6668 | 0.028667 |
| Fugue text (baseline) remote keystroke + value on 30000 chars | 326.1950 | 0.3262 | 0.000326 |
| Rich text remote keystroke + value on 30000 chars | 376.0600 | 0.3761 | 0.000376 |
| Rich text (marked lines) remote keystroke + value on 30000 chars | 498.8000 | 0.4988 | 0.000499 |
| Rich text remote format bold on/off + value on 30000 chars | 311.0100 | 0.3110 | 0.000311 |
| Rich text (marked lines) remote format bold on/off + value on 30000 chars | 638.9500 | 0.6390 | 0.000639 |
| Fugue text (baseline) takeSnapshot of 10000 elements | 1081.7094 | 1.0817 | 0.001082 |
| Fugue text (baseline) restore of 10000 elements from snapshot | 1105.2542 | 1.1053 | 0.001105 |
| Rich text (marked lines) takeSnapshot of 10000 elements | 3984.0965 | 3.9841 | 0.003984 |
| Rich text (marked lines) restore of 10000 elements from snapshot | 6835.2880 | 6.8353 | 0.006835 |
| Fugue text (baseline) takeSnapshot of 100000 elements | 42781.0000 | 42.7810 | 0.042781 |
| Fugue text (baseline) restore of 100000 elements from snapshot | 28795.1000 | 28.7951 | 0.028795 |
| Rich text (marked lines) takeSnapshot of 100000 elements | 114507.4500 | 114.5074 | 0.114507 |
| Rich text (marked lines) restore of 100000 elements from snapshot | 124206.4000 | 124.2064 | 0.124206 |
| Rich text undo+redo a bold format on 30000 chars | 38.7500 | 0.0387 | 0.000039 |
| Rich text (marked lines) undo+redo a bold format on 30000 chars | 526.7500 | 0.5268 | 0.000527 |
| Fugue text (baseline) undo+redo a 1-char delete on 30000 chars | 4.4000 | 0.0044 | 0.000004 |
| Rich text undo+redo a 1-char delete on 30000 chars | 6.8000 | 0.0068 | 0.000007 |
| Rich text (marked lines) undo+redo a 1-char delete on 30000 chars | 21.5000 | 0.0215 | 0.000022 |
| Fugue text (baseline) undo+redo a 100-char delete on 30000 chars | 65.1500 | 0.0651 | 0.000065 |
| Rich text undo+redo a 100-char delete on 30000 chars | 66.0000 | 0.0660 | 0.000066 |
| Rich text (marked lines) undo+redo a 100-char delete on 30000 chars | 208.8500 | 0.2089 | 0.000209 |
| Fugue text (baseline) undo+redo a 500-char delete on 30000 chars | 390.3000 | 0.3903 | 0.000390 |
| Rich text undo+redo a 500-char delete on 30000 chars | 471.2000 | 0.4712 | 0.000471 |
| Rich text (marked lines) undo+redo a 500-char delete on 30000 chars | 2143.3500 | 2.1433 | 0.002143 |

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

