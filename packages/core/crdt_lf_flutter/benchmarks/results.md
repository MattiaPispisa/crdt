### rich_text_field_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Rich text: one keystroke at the end, 1000 chars | 85.1900 | 0.0852 | 0.000085 |
| Rich text: one keystroke at the end, 10000 chars | 189.7800 | 0.1898 | 0.000190 |
| Rich text: one keystroke at the end, 50000 chars | 685.6100 | 0.6856 | 0.000686 |
| Rich text: one keystroke in the middle, 10000 chars | 130.8000 | 0.1308 | 0.000131 |
| Rich text: bold a 50-char selection, 10000 chars | 146.8700 | 0.1469 | 0.000147 |
| Rich text: bold a 50-char selection, 50000 chars | 906.9600 | 0.9070 | 0.000907 |
| Rich text: 6 format states of a select-all, 10000 chars | 4.4100 | 0.0044 | 0.000004 |
| Rich text: 6 format states of a select-all, 50000 chars | 24.8700 | 0.0249 | 0.000025 |
| Rich text: adopt one remote keystroke, 10000 chars | 95.8400 | 0.0958 | 0.000096 |
| Rich text: adopt one remote format, 10000 chars | 74.0000 | 0.0740 | 0.000074 |
| Rich text: adopt one remote keystroke, 50000 chars | 317.6000 | 0.3176 | 0.000318 |
| Rich text: adopt one remote format, 50000 chars | 201.8300 | 0.2018 | 0.000202 |
| Rich text: type, undo and redo one char, 10000 chars | 1138.3800 | 1.1384 | 0.001138 |

### text_field_benchmark.dart

| Benchmark | RunTime (us) | RunTime (ms) | RunTime (s) |
| --- | --- | --- | --- |
| Fugue text: one keystroke at the end, 1000 chars | 64.2400 | 0.0642 | 0.000064 |
| Fugue text: one keystroke at the end, 10000 chars | 119.8800 | 0.1199 | 0.000120 |
| Fugue text: one keystroke at the end, 50000 chars | 436.6200 | 0.4366 | 0.000437 |
| Fugue text: one keystroke in the middle, 10000 chars | 81.9200 | 0.0819 | 0.000082 |
| Index text: one keystroke at the end, 10000 chars | 107.9800 | 0.1080 | 0.000108 |
| Fugue text: adopt one remote keystroke, 10000 chars | 56.7500 | 0.0568 | 0.000057 |
| Fugue text: adopt one remote keystroke, 50000 chars | 135.3200 | 0.1353 | 0.000135 |
| Handler only: insert one char, 10000 chars | 2.0900 | 0.0021 | 0.000002 |
| Handler only: insert one char and read, 10000 chars | 73.9800 | 0.0740 | 0.000074 |
| Handler only: insert one char, 50000 chars | 2.2600 | 0.0023 | 0.000002 |
| Handler only: insert one char and read, 50000 chars | 539.1600 | 0.5392 | 0.000539 |
| No binding: one keystroke on a bare controller, 10000 chars | 17.9700 | 0.0180 | 0.000018 |

