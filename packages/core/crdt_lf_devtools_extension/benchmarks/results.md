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
| First sync of 10000 changes, idle app | 12483.6667 | 12.4837 | 0.012484 |
| First sync of 10000 changes, one edit per page | 13508.0000 | 13.5080 | 0.013508 |
| First sync of 10000 changes, a quiet peer | 12713.6667 | 12.7137 | 0.012714 |
| Sync of 10000 older remote changes into 10000 changes | 28205.0000 | 28.2050 | 0.028205 |
| First sync of 50000 changes, idle app | 65519.6667 | 65.5197 | 0.065520 |
| First sync of 50000 changes, one edit per page | 70636.3333 | 70.6363 | 0.070636 |
| First sync of 50000 changes, a quiet peer | 66619.3333 | 66.6193 | 0.066619 |
| Sync of 10000 older remote changes into 50000 changes | 41317.0000 | 41.3170 | 0.041317 |

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

