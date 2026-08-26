### text_field_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text: one keystroke at the end, 1000 chars | 124.2800 | 0.1243 | 0.000124 |
| Fugue text: one keystroke at the end, 10000 chars | 113.4500 | 0.1135 | 0.000113 |
| Fugue text: one keystroke at the end, 50000 chars | 190.9800 | 0.1910 | 0.000191 |
| Fugue text: one keystroke in the middle, 10000 chars | 89.0600 | 0.0891 | 0.000089 |
| Index text: one keystroke at the end, 10000 chars | 79.7800 | 0.0798 | 0.000080 |
| Fugue text: adopt one remote keystroke, 10000 chars | 65.0800 | 0.0651 | 0.000065 |
| Fugue text: adopt one remote keystroke, 50000 chars | 80.7500 | 0.0808 | 0.000081 |
| Handler only: insert one char, 10000 chars | 5.1400 | 0.0051 | 0.000005 |
| Handler only: insert one char and read, 10000 chars | 77.1600 | 0.0772 | 0.000077 |
| Handler only: insert one char, 50000 chars | 8.7100 | 0.0087 | 0.000009 |
| Handler only: insert one char and read, 50000 chars | 642.9400 | 0.6429 | 0.000643 |
| No binding: one keystroke on a bare controller, 10000 chars | 18.2400 | 0.0182 | 0.000018 |

