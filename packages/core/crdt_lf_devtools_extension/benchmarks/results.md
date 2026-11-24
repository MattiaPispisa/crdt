### change_log_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Change log, one edit on 10000 changes | 65.3200 | 0.0653 | 0.000065 |
| Time travel, one edit on 10000 changes | 58.6000 | 0.0586 | 0.000059 |
| Change log, one edit on 50000 changes | 56.6200 | 0.0566 | 0.000057 |
| Time travel, one edit on 50000 changes | 53.9200 | 0.0539 | 0.000054 |

### change_paging_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| First sync of 10000 changes, idle app | 13524.0000 | 13.5240 | 0.013524 |
| First sync of 10000 changes, one edit per page | 14200.0000 | 14.2000 | 0.014200 |
| First sync of 50000 changes, idle app | 67301.0000 | 67.3010 | 0.067301 |
| First sync of 50000 changes, one edit per page | 72536.3333 | 72.5363 | 0.072536 |

### documents_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Edit of the selected document, 20 documents | 77.9000 | 0.0779 | 0.000078 |
| Edit of another document, 20 documents | 43.5800 | 0.0436 | 0.000044 |

### storage_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| snapshot call, 10000 keys | 14.3084 | 0.0143 | 0.000014 |
| snapshot call, 100000 keys | 14.1892 | 0.0142 | 0.000014 |

### tab_switch_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Back to the Changes tab, 10000 changes | 48546.8000 | 48.5468 | 0.048547 |
| Back to the Time travel tab, 10000 changes | 23433.0000 | 23.4330 | 0.023433 |
| Back to the Changes tab, 50000 changes | 66443.6000 | 66.4436 | 0.066444 |
| Back to the Time travel tab, 50000 changes | 37635.8000 | 37.6358 | 0.037636 |

