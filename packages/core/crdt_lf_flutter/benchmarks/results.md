### text_field_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text: one keystroke at the end, 1000 chars | 52.3400 | 0.0523 | 0.000052 |
| Fugue text: one keystroke at the end, 10000 chars | 59.5300 | 0.0595 | 0.000060 |
| Fugue text: one keystroke at the end, 50000 chars | 166.8200 | 0.1668 | 0.000167 |
| Fugue text: one keystroke in the middle, 10000 chars | 54.2300 | 0.0542 | 0.000054 |
| Index text: one keystroke at the end, 10000 chars | 55.3800 | 0.0554 | 0.000055 |
| Fugue text: adopt one remote keystroke, 10000 chars | 36.2200 | 0.0362 | 0.000036 |
| Fugue text: adopt one remote keystroke, 50000 chars | 54.4600 | 0.0545 | 0.000054 |
| Handler only: insert one char, 10000 chars | 2.3800 | 0.0024 | 0.000002 |
| Handler only: insert one char and read, 10000 chars | 75.5000 | 0.0755 | 0.000076 |
| Handler only: insert one char, 50000 chars | 2.5800 | 0.0026 | 0.000003 |
| Handler only: insert one char and read, 50000 chars | 522.5800 | 0.5226 | 0.000523 |
| No binding: one keystroke on a bare controller, 10000 chars | 17.8700 | 0.0179 | 0.000018 |

