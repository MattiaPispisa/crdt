### change_filter_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Id filter on 10000 changes | 120.0500 | 0.1201 | 0.000120 |
| Id filter on 50000 changes | 709.2000 | 0.7092 | 0.000709 |

### change_log_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Change log, one edit on 10000 changes | 64.7400 | 0.0647 | 0.000065 |
| Time travel, one edit on 10000 changes | 57.0200 | 0.0570 | 0.000057 |
| Change log, one edit on 50000 changes | 60.3000 | 0.0603 | 0.000060 |
| Time travel, one edit on 50000 changes | 54.2200 | 0.0542 | 0.000054 |

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
| Back to the Changes tab, 10000 changes | 48110.0000 | 48.1100 | 0.048110 |
| Back to the Time travel tab, 10000 changes | 21820.2000 | 21.8202 | 0.021820 |
| Back to the Changes tab, 50000 changes | 49694.4000 | 49.6944 | 0.049694 |
| Back to the Time travel tab, 50000 changes | 38038.0000 | 38.0380 | 0.038038 |

