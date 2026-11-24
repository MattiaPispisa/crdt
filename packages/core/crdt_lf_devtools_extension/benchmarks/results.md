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
| First sync of 10000 changes, idle app | 13659.0000 | 13.6590 | 0.013659 |
| First sync of 10000 changes, one edit per page | 12624.6667 | 12.6247 | 0.012625 |
| First sync of 50000 changes, idle app | 70562.3333 | 70.5623 | 0.070562 |
| First sync of 50000 changes, one edit per page | 72694.6667 | 72.6947 | 0.072695 |

### documents_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Edit of the selected document, 20 documents | 77.6900 | 0.0777 | 0.000078 |
| Edit of another document, 20 documents | 40.9400 | 0.0409 | 0.000041 |

### handlers_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| handlers call, a closed handler of 10000 changes | 10.1930 | 0.0102 | 0.000010 |
| handlers call, a closed handler of 50000 changes | 10.1226 | 0.0101 | 0.000010 |

### storage_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| snapshot call, 10000 keys | 14.3084 | 0.0143 | 0.000014 |
| snapshot call, 100000 keys | 14.1892 | 0.0142 | 0.000014 |

### tab_switch_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Back to the Changes tab, 10000 changes | 48110.0000 | 48.1100 | 0.048110 |
| Back to the Time travel tab, 10000 changes | 21820.2000 | 21.8202 | 0.021820 |
| Back to the Changes tab, 50000 changes | 49694.4000 | 49.6944 | 0.049694 |
| Back to the Time travel tab, 50000 changes | 38038.0000 | 38.0380 | 0.038038 |

