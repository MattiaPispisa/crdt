### text_field_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text: one keystroke at the end, 1000 chars | 44.0000 | 0.0440 | 0.000044 |
| Fugue text: one keystroke at the end, 10000 chars | 57.1600 | 0.0572 | 0.000057 |
| Fugue text: one keystroke at the end, 50000 chars | 161.8800 | 0.1619 | 0.000162 |
| Fugue text: one keystroke in the middle, 10000 chars | 52.1100 | 0.0521 | 0.000052 |
| Index text: one keystroke at the end, 10000 chars | 52.7300 | 0.0527 | 0.000053 |
| Fugue text: adopt one remote keystroke, 10000 chars | 34.8000 | 0.0348 | 0.000035 |
| Fugue text: adopt one remote keystroke, 50000 chars | 48.4100 | 0.0484 | 0.000048 |
| Handler only: insert one char, 10000 chars | 2.3600 | 0.0024 | 0.000002 |
| Handler only: insert one char and read, 10000 chars | 69.9200 | 0.0699 | 0.000070 |
| Handler only: insert one char, 50000 chars | 2.3900 | 0.0024 | 0.000002 |
| Handler only: insert one char and read, 50000 chars | 491.8400 | 0.4918 | 0.000492 |
| No binding: one keystroke on a bare controller, 10000 chars | 16.3000 | 0.0163 | 0.000016 |

