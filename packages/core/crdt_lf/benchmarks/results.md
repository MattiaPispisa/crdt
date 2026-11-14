### aggregate_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Aggregate dispatch + read | 1.4350 | 0.0014 | 0.000001 |
| Aggregate replay of 1000 events | 299.0709 | 0.2991 | 0.000299 |
| Aggregate remote event + read on 1000 events | 2.7500 | 0.0027 | 0.000003 |
| Aggregate remote event + read on 1000 events (from the past) | 328.1300 | 0.3281 | 0.000328 |

### apply_changes_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Apply 1000 changes | 781.4587 | 0.7815 | 0.000781 |

### apply_changes_capabilities_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Apply 1000 changes (capabilities tracked) | 820.9524 | 0.8210 | 0.000821 |

### change_roundtrip_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Change toBytes x1000 | 61.3385 | 0.0613 | 0.000061 |
| Change fromBytes x1000 | 15.1641 | 0.0152 | 0.000015 |
| Change roundtrip x1000 | 77.9573 | 0.0780 | 0.000078 |

### dag_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| DAG addNode chain of 1000 | 141.6343 | 0.1416 | 0.000142 |
| DAG getAncestors chain of 200 | 8.3247 | 0.0083 | 0.000008 |

### delete_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Remote delete with 100 open containers | 6.9650 | 0.0070 | 0.000007 |
| Remote delete with 1000 open containers | 6.2200 | 0.0062 | 0.000006 |
| Remote delete with 10000 open containers | 5.2300 | 0.0052 | 0.000005 |
| Remote delete after 100 deletes | 7.4550 | 0.0075 | 0.000007 |
| Remote delete after 1000 deletes | 31.7850 | 0.0318 | 0.000032 |
| Remote delete after 10000 deletes | 289.8650 | 0.2899 | 0.000290 |

### delta_emission_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text remote keystroke + read on 2000 chars (watched: false) | 43.5150 | 0.0435 | 0.000044 |
| Fugue text remote keystroke + read on 2000 chars (watched: true) | 34.8800 | 0.0349 | 0.000035 |
| Fugue text remote keystroke + read on 10000 chars (watched: false) | 91.9700 | 0.0920 | 0.000092 |
| Fugue text remote keystroke + read on 10000 chars (watched: true) | 88.5200 | 0.0885 | 0.000089 |
| Text remote keystroke + read on 2000 chars (watched: false) | 14.4700 | 0.0145 | 0.000014 |
| Text remote keystroke + read on 2000 chars (watched: true) | 22.0750 | 0.0221 | 0.000022 |
| Text remote keystroke + read on 10000 chars (watched: false) | 31.2800 | 0.0313 | 0.000031 |
| Text remote keystroke + read on 10000 chars (watched: true) | 47.6650 | 0.0477 | 0.000048 |
| Map remote write + read on 1000 keys (watched: false) | 7.1650 | 0.0072 | 0.000007 |
| Map remote write + read on 1000 keys (watched: true) | 10.3300 | 0.0103 | 0.000010 |
| Map remote write + read on 5000 keys (watched: false) | 4.2050 | 0.0042 | 0.000004 |
| Map remote write + read on 5000 keys (watched: true) | 5.3600 | 0.0054 | 0.000005 |
| Movable list remote move + read on 1000 elements (watched: false) | 57.7100 | 0.0577 | 0.000058 |
| Movable list remote move + read on 1000 elements (watched: true) | 78.9600 | 0.0790 | 0.000079 |
| Movable list remote move + read on 5000 elements (watched: false) | 187.1500 | 0.1872 | 0.000187 |
| Movable list remote move + read on 5000 elements (watched: true) | 358.2500 | 0.3583 | 0.000358 |
| Fugue text type 2000 chars locally (watched: false) | 43750.6600 | 43.7507 | 0.043751 |
| Fugue text type 2000 chars locally (watched: true) | 62523.8919 | 62.5239 | 0.062524 |

### fugue_list_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTFugueListHandler do 1000 operations and get value (incremental cache update: true) | 2472.7570 | 2.4728 | 0.002473 |

### fugue_snapshot_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text takeSnapshot of 10000 elements (tombstones: false) | 1042.2505 | 1.0423 | 0.001042 |
| Fugue text restore of 10000 elements from snapshot (tombstones: false) | 1222.5738 | 1.2226 | 0.001223 |
| Fugue text takeSnapshot of 10000 elements (tombstones: true) | 1176.0220 | 1.1760 | 0.001176 |
| Fugue text restore of 10000 elements from snapshot (tombstones: true) | 1720.9661 | 1.7210 | 0.001721 |
| Fugue text takeSnapshot of 100000 elements (tombstones: false) | 39596.6286 | 39.5966 | 0.039597 |
| Fugue text restore of 100000 elements from snapshot (tombstones: false) | 40582.5857 | 40.5826 | 0.040583 |
| Fugue text takeSnapshot of 100000 elements (tombstones: true) | 54714.1400 | 54.7141 | 0.054714 |
| Fugue text restore of 100000 elements from snapshot (tombstones: true) | 40639.4833 | 40.6395 | 0.040639 |

### fugue_text_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text keystroke + length on 30000 chars | 14.1700 | 0.0142 | 0.000014 |
| Fugue text keystroke + value on 30000 chars | 350.3250 | 0.3503 | 0.000350 |
| Fugue text update on 30000 chars | 1.6450 | 0.0016 | 0.000002 |

### fugue_tree_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| FugueTree append 50000 elements | 10983.7053 | 10.9837 | 0.010984 |
| FugueTree prepend 50000 elements | 94069.2000 | 94.0692 | 0.094069 |
| FugueTree random insert 50000 elements | 125595.1000 | 125.5951 | 0.125595 |
| FugueTree values() over 50000 live elements | 396.7918 | 0.3968 | 0.000397 |
| FugueTree values() over 50000 elements, 90% tombstones | 62.6973 | 0.0627 | 0.000063 |

### handler_count_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Local write + read with 100 handlers | 1.8250 | 0.0018 | 0.000002 |
| Local write + read with 1000 handlers | 1.5150 | 0.0015 | 0.000002 |
| Local write + read with 10000 handlers | 1.5200 | 0.0015 | 0.000002 |
| Remote applyChange + read with 100 handlers | 2.1800 | 0.0022 | 0.000002 |
| Remote applyChange + read with 1000 handlers | 1.7900 | 0.0018 | 0.000002 |
| Remote applyChange + read with 10000 handlers | 1.8300 | 0.0018 | 0.000002 |
| importChanges of 100 changes with 100 handlers | 124.6200 | 0.1246 | 0.000125 |
| importChanges of 100 changes with 1000 handlers | 125.4100 | 0.1254 | 0.000125 |
| importChanges of 100 changes with 10000 handlers | 130.6450 | 0.1306 | 0.000131 |

### list_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTListHandler do 1000 operations and get value (incremental cache update: true) | 1859.0808 | 1.8591 | 0.001859 |

### map_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTMapHandler do 1000 operations and get value (incremental cache update: true) | 1981.6598 | 1.9817 | 0.001982 |

### nested_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Resolve nested tree with 50 leaves (cold caches) | 110.6563 | 0.1107 | 0.000111 |
| Resolve nested tree with 200 leaves (cold caches) | 467.3413 | 0.4673 | 0.000467 |
| Resolve nested tree with 800 leaves (cold caches) | 1966.8524 | 1.9669 | 0.001967 |
| Import + resolve nested tree with 50 leaves (fresh peer) | 158.7506 | 0.1588 | 0.000159 |
| Import + resolve nested tree with 200 leaves (fresh peer) | 591.6798 | 0.5917 | 0.000592 |
| Import + resolve nested tree with 800 leaves (fresh peer) | 2297.7656 | 2.2978 | 0.002298 |

### op_id_key_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| OpIdKey view x100k | 486.1575 | 0.4862 | 0.000486 |
| OpIdKey hashCode x100k (cold) | 1804.2866 | 1.8043 | 0.001804 |
| OpIdKey map lookup x10k | 69.3590 | 0.0694 | 0.000069 |
| OperationId map lookup x10k | 57.6379 | 0.0576 | 0.000058 |

### or_set_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTORSetHandler do 1000 operations and get value (incremental cache update: true) | 2048.2135 | 2.0482 | 0.002048 |

### peer_id_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| PeerId generate x100 | 195.4523 | 0.1955 | 0.000195 |
| PeerId toUint8List x1000 | 32.8954 | 0.0329 | 0.000033 |
| PeerId fromUint8List x1000 | 53.8740 | 0.0539 | 0.000054 |

### remote_apply_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text remote keystroke + read on 2000 chars | 46.5150 | 0.0465 | 0.000047 |
| Fugue text remote keystroke + read on 10000 chars | 102.1800 | 0.1022 | 0.000102 |
| Fugue text remote keystroke + read on 30000 chars | 344.6800 | 0.3447 | 0.000345 |
| Text remote keystroke + read on 2000 chars | 15.9200 | 0.0159 | 0.000016 |
| Text remote keystroke + read on 10000 chars | 32.0700 | 0.0321 | 0.000032 |
| Text remote keystroke + read on 30000 chars | 74.0150 | 0.0740 | 0.000074 |
| Map remote set + read on 1000 keys | 12.3300 | 0.0123 | 0.000012 |
| Map remote set + read on 5000 keys | 4.4300 | 0.0044 | 0.000004 |
| OR-set remote add from the past + read on 1000 values | 36.2400 | 0.0362 | 0.000036 |
| OR-set remote add from the past + read on 5000 values | 98.8300 | 0.0988 | 0.000099 |
| OR-map remote put from the past + read on 1000 keys | 63.7100 | 0.0637 | 0.000064 |
| OR-map remote put from the past + read on 5000 keys | 245.7650 | 0.2458 | 0.000246 |
| Movable list remote move from the past + read on 1000 items | 51.0100 | 0.0510 | 0.000051 |
| Movable list remote move from the past + read on 5000 items | 186.5400 | 0.1865 | 0.000187 |

### rich_text_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text (baseline) keystroke + length on 30000 chars | 16.0550 | 0.0161 | 0.000016 |
| Fugue text (baseline) keystroke + value on 30000 chars | 334.2550 | 0.3343 | 0.000334 |
| Fugue text (baseline) delete + length on 30000 chars | 1.5350 | 0.0015 | 0.000002 |
| Fugue text (baseline) delete + value on 30000 chars | 305.1850 | 0.3052 | 0.000305 |
| Rich text keystroke + length on 30000 chars | 10.1850 | 0.0102 | 0.000010 |
| Rich text keystroke + value on 30000 chars | 357.7100 | 0.3577 | 0.000358 |
| Rich text delete + length on 30000 chars | 1.7950 | 0.0018 | 0.000002 |
| Rich text delete + value on 30000 chars | 323.5650 | 0.3236 | 0.000324 |
| Rich text (marked lines) keystroke + length on 30000 chars | 27.8650 | 0.0279 | 0.000028 |
| Rich text (marked lines) keystroke + value on 30000 chars | 527.7600 | 0.5278 | 0.000528 |
| Rich text (marked lines) delete + length on 30000 chars | 14.1250 | 0.0141 | 0.000014 |
| Rich text (marked lines) delete + value on 30000 chars | 384.1850 | 0.3842 | 0.000384 |
| Fugue text (baseline) insert 100 lines (watched: false) | 672.6000 | 0.6726 | 0.000673 |
| Rich text insert 100 lines (watched: false) | 671.3000 | 0.6713 | 0.000671 |
| Rich text insert 100 lines x 3 attributes (watched: false) | 2218.3000 | 2.2183 | 0.002218 |
| Fugue text (baseline) insert 100 lines (watched: true) | 671.3000 | 0.6713 | 0.000671 |
| Rich text insert 100 lines (watched: true) | 960.5000 | 0.9605 | 0.000960 |
| Rich text insert 100 lines x 3 attributes (watched: true) | 3341.2000 | 3.3412 | 0.003341 |
| Fugue text (baseline) insert 1000 lines (watched: false) | 9939.9000 | 9.9399 | 0.009940 |
| Rich text insert 1000 lines (watched: false) | 9646.3000 | 9.6463 | 0.009646 |
| Rich text insert 1000 lines x 3 attributes (watched: false) | 25368.0000 | 25.3680 | 0.025368 |
| Fugue text (baseline) insert 1000 lines (watched: true) | 10075.6000 | 10.0756 | 0.010076 |
| Rich text insert 1000 lines (watched: true) | 10275.4000 | 10.2754 | 0.010275 |
| Rich text insert 1000 lines x 3 attributes (watched: true) | 75373.6000 | 75.3736 | 0.075374 |
| Rich text format bold on/off + length on 30000 chars (watched: false) | 7.1300 | 0.0071 | 0.000007 |
| Rich text format bold on/off + length on 30000 chars (watched: true) | 8.0800 | 0.0081 | 0.000008 |
| Rich text (marked lines) format bold on/off + length on 30000 chars (watched: false) | 445.3600 | 0.4454 | 0.000445 |
| Rich text (marked lines) format bold on/off + length on 30000 chars (watched: true) | 666.8900 | 0.6669 | 0.000667 |
| Rich text keystroke after deleting half of 30000 chars, with a link | 32.0900 | 0.0321 | 0.000032 |
| Fugue text (baseline) import 1000 line inserts + value | 15488.7000 | 15.4887 | 0.015489 |
| Rich text import 1000 line inserts + value | 11911.2000 | 11.9112 | 0.011911 |
| Rich text (marked lines) import 1000 line inserts + value | 28524.5000 | 28.5245 | 0.028525 |
| Fugue text (baseline) remote keystroke + value on 30000 chars | 346.0550 | 0.3461 | 0.000346 |
| Rich text remote keystroke + value on 30000 chars | 357.6800 | 0.3577 | 0.000358 |
| Rich text (marked lines) remote keystroke + value on 30000 chars | 471.8750 | 0.4719 | 0.000472 |
| Rich text remote format bold on/off + value on 30000 chars | 311.8550 | 0.3119 | 0.000312 |
| Rich text (marked lines) remote format bold on/off + value on 30000 chars | 664.4500 | 0.6645 | 0.000664 |
| Fugue text (baseline) takeSnapshot of 10000 elements | 1134.5780 | 1.1346 | 0.001135 |
| Fugue text (baseline) restore of 10000 elements from snapshot | 2265.0388 | 2.2650 | 0.002265 |
| Rich text (marked lines) takeSnapshot of 10000 elements | 2397.2483 | 2.3972 | 0.002397 |
| Rich text (marked lines) restore of 10000 elements from snapshot | 10685.3059 | 10.6853 | 0.010685 |
| Fugue text (baseline) takeSnapshot of 100000 elements | 59216.3727 | 59.2164 | 0.059216 |
| Fugue text (baseline) restore of 100000 elements from snapshot | 46017.5333 | 46.0175 | 0.046018 |
| Rich text (marked lines) takeSnapshot of 100000 elements | 142094.4000 | 142.0944 | 0.142094 |
| Rich text (marked lines) restore of 100000 elements from snapshot | 112996.9000 | 112.9969 | 0.112997 |
| Rich text undo+redo a bold format on 30000 chars | 34.1000 | 0.0341 | 0.000034 |
| Rich text (marked lines) undo+redo a bold format on 30000 chars | 504.8000 | 0.5048 | 0.000505 |
| Rich text (marked lines) undo+redo a 5-char color format on 30000 chars | 38.3500 | 0.0384 | 0.000038 |
| Fugue text (baseline) undo+redo a 1-char delete on 30000 chars | 4.5500 | 0.0046 | 0.000005 |
| Rich text undo+redo a 1-char delete on 30000 chars | 6.7500 | 0.0067 | 0.000007 |
| Rich text (marked lines) undo+redo a 1-char delete on 30000 chars | 21.7000 | 0.0217 | 0.000022 |
| Fugue text (baseline) undo+redo a 100-char delete on 30000 chars | 66.6000 | 0.0666 | 0.000067 |
| Rich text undo+redo a 100-char delete on 30000 chars | 69.6000 | 0.0696 | 0.000070 |
| Rich text (marked lines) undo+redo a 100-char delete on 30000 chars | 205.9500 | 0.2059 | 0.000206 |
| Fugue text (baseline) undo+redo a 500-char delete on 30000 chars | 402.5000 | 0.4025 | 0.000403 |
| Rich text undo+redo a 500-char delete on 30000 chars | 2788.5500 | 2.7886 | 0.002789 |
| Rich text (marked lines) undo+redo a 500-char delete on 30000 chars | 8230.7500 | 8.2308 | 0.008231 |
| Rich text (marked lines) remote delete + length on a cold cache (watched) | 56.7450 | 0.0567 | 0.000057 |

### scaling_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Import 1000 chained changes | 821.8071 | 0.8218 | 0.000822 |
| Import 10000 chained changes | 9507.3190 | 9.5073 | 0.009507 |
| exportChangesNewerThan on 50000 changes / 10 peers (99% caught-up) | 2.0016 | 0.0020 | 0.000002 |
| takeSnapshot(pruneHistory) with 10000 changes | 18660.2818 | 18.6603 | 0.018660 |
| takeSnapshot(pruneHistory) with 100 concurrent heads | 3605.6893 | 3.6057 | 0.003606 |

### serialization_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Binary encode/decode 1000 changes | 1123.8469 | 1.1238 | 0.001124 |

### snapshot_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Take snapshot with 1000 changes | 135.0754 | 0.1351 | 0.000135 |

### text_handler_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| CRDTTextHandler do 1000 operations and get value (incremental cache update: true) | 3465.5793 | 3.4656 | 0.003466 |
| CRDTTextHandler do 1000 operations and get value (incremental cache update: false) | 2325.5093 | 2.3255 | 0.002326 |

### topological_sort_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Import 1000 concurrent changes | 809.9756 | 0.8100 | 0.000810 |

### undo_manager_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text type 300 chars locally (undo managers: 0) | 589.0667 | 0.5891 | 0.000589 |
| Fugue text type 300 chars locally (undo managers: 1) | 714.7667 | 0.7148 | 0.000715 |
| Fugue text type 300 chars locally (undo managers: 2) | 670.3000 | 0.6703 | 0.000670 |
| Fugue text type 300 chars locally (undo managers: 3) | 671.3000 | 0.6713 | 0.000671 |
| Fugue text type 300 chars locally (undo managers: 5) | 676.0667 | 0.6761 | 0.000676 |
| Fugue text undo+redo one keystroke on 2000 chars | 4.1500 | 0.0042 | 0.000004 |
| Fugue text undo+redo one keystroke on 10000 chars | 4.1000 | 0.0041 | 0.000004 |
| Fugue text undo+redo a 1-char delete on 5000 chars | 4.0500 | 0.0040 | 0.000004 |
| Fugue text undo+redo a 100-char delete on 5000 chars | 57.5000 | 0.0575 | 0.000058 |
| Fugue text undo+redo a 500-char delete on 5000 chars | 374.7000 | 0.3747 | 0.000375 |
| Map undo+redo one set on 5000 keys | 3.3000 | 0.0033 | 0.000003 |
| OR-set undo+redo one add on 5000 values | 3.7500 | 0.0037 | 0.000004 |
| Fugue text undo/redo ping-pong x10 on 2000 chars | 690.0000 | 0.6900 | 0.000690 |
| Fugue text undo/redo ping-pong x100 on 2000 chars | 1299.6667 | 1.2997 | 0.001300 |
| Fugue text undo/redo ping-pong x1000 on 2000 chars | 11421.3333 | 11.4213 | 0.011421 |

### version_vector_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| VersionVector toBytes 10 peers x1000 | 457.5984 | 0.4576 | 0.000458 |
| VersionVector fromBytes 10 peers x1000 | 678.2669 | 0.6783 | 0.000678 |
| VersionVector intersection 10 peers x1000 | 214.5109 | 0.2145 | 0.000215 |

