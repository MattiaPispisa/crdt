### change_filter_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Id filter on 10000 changes | 142.1000 | 0.1421 | 0.000142 |
| Id filter on 50000 changes | 833.9000 | 0.8339 | 0.000834 |

### change_log_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Change log, one edit on 10000 changes | 63.8400 | 0.0638 | 0.000064 |
| Time travel, one edit on 10000 changes | 56.8200 | 0.0568 | 0.000057 |
| Change log, one edit and a concurrent remote one on 10000 changes | 61.3200 | 0.0613 | 0.000061 |
| Time travel, one edit and a concurrent remote one on 10000 changes | 60.0600 | 0.0601 | 0.000060 |
| Change log, one edit on 50000 changes | 56.6400 | 0.0566 | 0.000057 |
| Time travel, one edit on 50000 changes | 54.7600 | 0.0548 | 0.000055 |
| Change log, one edit and a concurrent remote one on 50000 changes | 61.0800 | 0.0611 | 0.000061 |
| Time travel, one edit and a concurrent remote one on 50000 changes | 60.1000 | 0.0601 | 0.000060 |

### change_paging_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| First sync of 10000 changes, idle app | 13537.0000 | 13.5370 | 0.013537 |
| First sync of 10000 changes, one edit per page | 13629.3333 | 13.6293 | 0.013629 |
| First sync of 10000 changes, a quiet peer | 13015.6667 | 13.0157 | 0.013016 |
| Sync of 10000 older remote changes into 10000 changes | 13972.0000 | 13.9720 | 0.013972 |
| Sync of 10000 changes after a prune that removes nothing | 693.0000 | 0.6930 | 0.000693 |
| First sync of 50000 changes, idle app | 66713.0000 | 66.7130 | 0.066713 |
| First sync of 50000 changes, one edit per page | 72831.6667 | 72.8317 | 0.072832 |
| First sync of 50000 changes, a quiet peer | 65838.0000 | 65.8380 | 0.065838 |
| Sync of 10000 older remote changes into 50000 changes | 25521.0000 | 25.5210 | 0.025521 |
| Sync of 50000 changes after a prune that removes nothing | 3359.6667 | 3.3597 | 0.003360 |

### changes_tab_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Edit with the Changes tab open, 10 handlers | 7184.6000 | 7.1846 | 0.007185 |
| Edit with the Changes tab open, 1000 handlers | 4682.6000 | 4.6826 | 0.004683 |
| Edit with the Changes tab open, 5000 handlers | 4183.0000 | 4.1830 | 0.004183 |

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
| Value change, 200 maps of 5 fields | 11561.8000 | 11.5618 | 0.011562 |
| Value change, 200 maps of 20 fields | 10726.2000 | 10.7262 | 0.010726 |

