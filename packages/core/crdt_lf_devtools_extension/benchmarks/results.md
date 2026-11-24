### change_filter_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Id filter on 10000 changes | 142.1000 | 0.1421 | 0.000142 |
| Id filter on 50000 changes | 833.9000 | 0.8339 | 0.000834 |

### change_log_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Change log, one edit on 10000 changes | 63.8600 | 0.0639 | 0.000064 |
| Time travel, one edit on 10000 changes | 57.1200 | 0.0571 | 0.000057 |
| Change log, one edit and a concurrent remote one on 10000 changes | 61.7000 | 0.0617 | 0.000062 |
| Time travel, one edit and a concurrent remote one on 10000 changes | 59.8400 | 0.0598 | 0.000060 |
| Change log, one edit on 50000 changes | 58.2200 | 0.0582 | 0.000058 |
| Time travel, one edit on 50000 changes | 57.0800 | 0.0571 | 0.000057 |
| Change log, one edit and a concurrent remote one on 50000 changes | 65.4200 | 0.0654 | 0.000065 |
| Time travel, one edit and a concurrent remote one on 50000 changes | 60.2600 | 0.0603 | 0.000060 |

### change_paging_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| First sync of 10000 changes, idle app | 13537.0000 | 13.5370 | 0.013537 |
| First sync of 10000 changes, one edit per page | 13629.3333 | 13.6293 | 0.013629 |
| First sync of 10000 changes, a quiet peer | 13015.6667 | 13.0157 | 0.013016 |
| Sync of 10000 older remote changes into 10000 changes | 13972.0000 | 13.9720 | 0.013972 |
| Prune that removes nothing and sync, 10000 changes | 693.0000 | 0.6930 | 0.000693 |
| First sync of 50000 changes, idle app | 66713.0000 | 66.7130 | 0.066713 |
| First sync of 50000 changes, one edit per page | 72831.6667 | 72.8317 | 0.072832 |
| First sync of 50000 changes, a quiet peer | 65838.0000 | 65.8380 | 0.065838 |
| Sync of 10000 older remote changes into 50000 changes | 25521.0000 | 25.5210 | 0.025521 |
| Prune that removes nothing and sync, 50000 changes | 3359.6667 | 3.3597 | 0.003360 |

### changes_tab_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Edit with the Changes tab open, 10 handlers | 4746.2000 | 4.7462 | 0.004746 |
| Edit with the Changes tab open, 1000 handlers | 3998.2000 | 3.9982 | 0.003998 |
| Edit with the Changes tab open, 5000 handlers | 3971.3000 | 3.9713 | 0.003971 |

### documents_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Edit of the selected document, 20 documents | 77.6900 | 0.0777 | 0.000078 |
| Edit of another document, 20 documents | 40.9400 | 0.0409 | 0.000041 |

### handlers_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Repeated handlers call, a closed handler of 10000 changes | 9.7783 | 0.0098 | 0.000010 |
| Repeated handlers call, a closed handler of 50000 changes | 9.6090 | 0.0096 | 0.000010 |

### storage_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Repeated snapshot call, 10000 keys | 14.0650 | 0.0141 | 0.000014 |
| Repeated snapshot call, 100000 keys | 13.8442 | 0.0138 | 0.000014 |

### storage_tab_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Edit with the Storage tab open, 10 handlers | 1705.8000 | 1.7058 | 0.001706 |
| Edit with the Storage tab open, 1000 handlers | 2868.2000 | 2.8682 | 0.002868 |
| Edit with the Storage tab open, 5000 handlers | 5499.3000 | 5.4993 | 0.005499 |

### tab_switch_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Back to the Changes tab, 10000 changes | 45106.4000 | 45.1064 | 0.045106 |
| Back to the Time travel tab, 10000 changes | 20598.2000 | 20.5982 | 0.020598 |
| Back to the Changes tab, 50000 changes | 60274.4000 | 60.2744 | 0.060274 |
| Back to the Time travel tab, 50000 changes | 36903.4000 | 36.9034 | 0.036903 |

### value_tree_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Value change, 20 maps of 10 fields | 13705.0000 | 13.7050 | 0.013705 |
| Value change, 200 maps of 5 fields | 9944.0000 | 9.9440 | 0.009944 |
| Value change, 200 maps of 20 fields | 11656.2000 | 11.6562 | 0.011656 |
| Value change, 20 maps of 200 fields, grown from 1 | 2797.8000 | 2.7978 | 0.002798 |

