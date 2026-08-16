Apply 1000 changes(RunTime): 9491.848341232228 us | 9.4918 ms | 0.009492 s
Change toBytes x1000(RunTime): 597.75375 us | 0.5978 ms | 0.000598 s
Change fromBytes x1000(RunTime): 187.7515923566879 us | 0.1878 ms | 0.000188 s
Change roundtrip x1000(RunTime): 793.0705 us | 0.7931 ms | 0.000793 s
DAG addNode chain of 1000(RunTime): 1839.1941529235382 us | 1.8392 ms | 0.001839 s
DAG getAncestors chain of 200(RunTime): 72.93685431543842 us | 0.0729 ms | 0.000073 s
CRDTFugueListHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 32759.238095238095 us | 32.7592 ms | 0.032759 s
FugueTree append 50000 elements(RunTime): 299967.5714285714 us | 299.9676 ms | 0.299968 s
FugueTree prepend 50000 elements(RunTime): 733335.3333333334 us | 733.3353 ms | 0.733335 s
FugueTree random insert 50000 elements(RunTime): 759692.3333333334 us | 759.6923 ms | 0.759692 s
FugueTree values() over 50000 live elements(RunTime): 8659.131355932202 us | 8.6591 ms | 0.008659 s
FugueTree values() over 50000 elements, 90% tombstones(RunTime): 1270.3155 us | 1.2703 ms | 0.001270 s
HLC toUint8List x100k(RunTime): 253.5679500254972 us | 0.2536 ms | 0.000254 s
HLC fromUint8List x100k(RunTime): 5025.7925 us | 5.0258 ms | 0.005026 s
HLC compareTo x100k(RunTime): 455.7771812080537 us | 0.4558 ms | 0.000456 s
CRDTListHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 25980.697368421053 us | 25.9807 ms | 0.025981 s
CRDTMapHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 26066.59493670886 us | 26.0666 ms | 0.026067 s
Resolve nested tree with 50 leaves (cold caches)(RunTime): 1902.7001499250375 us | 1.9027 ms | 0.001903 s
Resolve nested tree with 200 leaves (cold caches)(RunTime): 8323.032 us | 8.3230 ms | 0.008323 s
