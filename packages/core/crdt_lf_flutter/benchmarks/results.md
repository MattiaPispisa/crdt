### rich_text_field_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Rich text: one keystroke at the end, 1000 chars | 59.5400 | 0.0595 | 0.000060 |
| Rich text: one keystroke at the end, 10000 chars | 93.4000 | 0.0934 | 0.000093 |
| Rich text: one keystroke at the end, 50000 chars | 295.7200 | 0.2957 | 0.000296 |
| Rich text: one keystroke in the middle, 10000 chars | 79.5300 | 0.0795 | 0.000080 |
| Rich text: bold a 50-char selection, 10000 chars | 121.3600 | 0.1214 | 0.000121 |
| Rich text: bold a 50-char selection, 50000 chars | 877.8300 | 0.8778 | 0.000878 |
| Rich text: adopt one remote keystroke, 10000 chars | 63.2700 | 0.0633 | 0.000063 |
| Rich text: adopt one remote format, 10000 chars | 50.5500 | 0.0505 | 0.000051 |
| Rich text: adopt one remote keystroke, 50000 chars | 152.1900 | 0.1522 | 0.000152 |
| Rich text: adopt one remote format, 50000 chars | 117.0200 | 0.1170 | 0.000117 |
| Rich text: type, undo and redo one char, 10000 chars | 405.1800 | 0.4052 | 0.000405 |

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

