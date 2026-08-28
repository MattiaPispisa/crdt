### text_field_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text: one keystroke at the end, 1000 chars | 45.4800 | 0.0455 | 0.000045 |
| Fugue text: one keystroke at the end, 10000 chars | 56.9500 | 0.0570 | 0.000057 |
| Fugue text: one keystroke at the end, 50000 chars | 162.0700 | 0.1621 | 0.000162 |
| Fugue text: one keystroke in the middle, 10000 chars | 50.6000 | 0.0506 | 0.000051 |
| Index text: one keystroke at the end, 10000 chars | 53.5200 | 0.0535 | 0.000054 |
| Fugue text: adopt one remote keystroke, 10000 chars | 35.0200 | 0.0350 | 0.000035 |
| Fugue text: adopt one remote keystroke, 50000 chars | 61.6000 | 0.0616 | 0.000062 |
| Handler only: insert one char, 10000 chars | 2.1900 | 0.0022 | 0.000002 |
| Handler only: insert one char and read, 10000 chars | 70.8900 | 0.0709 | 0.000071 |
| Handler only: insert one char, 50000 chars | 2.4400 | 0.0024 | 0.000002 |
| Handler only: insert one char and read, 50000 chars | 501.8600 | 0.5019 | 0.000502 |
| No binding: one keystroke on a bare controller, 10000 chars | 16.4500 | 0.0164 | 0.000016 |

