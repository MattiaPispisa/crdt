### change_filter_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Id filter on 10000 changes | 142.1000 | 0.1421 | 0.000142 |
| Id filter on 50000 changes | 833.9000 | 0.8339 | 0.000834 |

### change_log_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Change log, one edit on 10000 changes | 60.4800 | 0.0605 | 0.000060 |
| Time travel, one edit on 10000 changes | 54.3800 | 0.0544 | 0.000054 |
| Change log, one edit and an older remote one on 10000 changes | 65.1400 | 0.0651 | 0.000065 |
| Time travel, one edit and an older remote one on 10000 changes | 62.1400 | 0.0621 | 0.000062 |
| Change log, one edit on 50000 changes | 56.1400 | 0.0561 | 0.000056 |
| Time travel, one edit on 50000 changes | 51.2000 | 0.0512 | 0.000051 |
| Change log, one edit and an older remote one on 50000 changes | 65.8400 | 0.0658 | 0.000066 |
| Time travel, one edit and an older remote one on 50000 changes | 61.9000 | 0.0619 | 0.000062 |

### change_paging_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| First sync of 10000 changes, idle app | 13419.0000 | 13.4190 | 0.013419 |
| First sync of 10000 changes, one edit per page | 13267.3333 | 13.2673 | 0.013267 |
| First sync of 10000 changes, a quiet peer | 13192.3333 | 13.1923 | 0.013192 |
| First sync of 50000 changes, idle app | 65385.6667 | 65.3857 | 0.065386 |
| First sync of 50000 changes, one edit per page | 70608.3333 | 70.6083 | 0.070608 |
| First sync of 50000 changes, a quiet peer | 64854.6667 | 64.8547 | 0.064855 |

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

