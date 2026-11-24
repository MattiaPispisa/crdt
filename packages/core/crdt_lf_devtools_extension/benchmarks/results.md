### change_filter_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Id filter on 10000 changes | 142.1000 | 0.1421 | 0.000142 |
| Id filter on 50000 changes | 833.9000 | 0.8339 | 0.000834 |

### change_log_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Change log, one edit on 10000 changes | 61.5800 | 0.0616 | 0.000062 |
| Time travel, one edit on 10000 changes | 53.4800 | 0.0535 | 0.000053 |
| Change log, one edit and a concurrent remote one on 10000 changes | 67.0600 | 0.0671 | 0.000067 |
| Time travel, one edit and a concurrent remote one on 10000 changes | 65.4600 | 0.0655 | 0.000065 |
| Change log, one edit on 50000 changes | 53.0400 | 0.0530 | 0.000053 |
| Time travel, one edit on 50000 changes | 53.0600 | 0.0531 | 0.000053 |
| Change log, one edit and a concurrent remote one on 50000 changes | 68.9800 | 0.0690 | 0.000069 |
| Time travel, one edit and a concurrent remote one on 50000 changes | 66.6800 | 0.0667 | 0.000067 |

### change_paging_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| First sync of 10000 changes, idle app | 12679.0000 | 12.6790 | 0.012679 |
| First sync of 10000 changes, one edit per page | 12655.3333 | 12.6553 | 0.012655 |
| First sync of 10000 changes, a quiet peer | 12758.0000 | 12.7580 | 0.012758 |
| Sync of 10000 older remote changes into 10000 changes | 13794.0000 | 13.7940 | 0.013794 |
| First sync of 50000 changes, idle app | 62260.3333 | 62.2603 | 0.062260 |
| First sync of 50000 changes, one edit per page | 66109.3333 | 66.1093 | 0.066109 |
| First sync of 50000 changes, a quiet peer | 58985.6667 | 58.9857 | 0.058986 |
| Sync of 10000 older remote changes into 50000 changes | 23834.0000 | 23.8340 | 0.023834 |

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
| Back to the Changes tab, 10000 changes | 45353.0000 | 45.3530 | 0.045353 |
| Back to the Time travel tab, 10000 changes | 21689.8000 | 21.6898 | 0.021690 |
| Back to the Changes tab, 50000 changes | 46998.6000 | 46.9986 | 0.046999 |
| Back to the Time travel tab, 50000 changes | 38511.4000 | 38.5114 | 0.038511 |

