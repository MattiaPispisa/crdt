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
Resolve nested tree with 800 leaves (cold caches)(RunTime): 34795.91525423729 us | 34.7959 ms | 0.034796 s
Import + resolve nested tree with 50 leaves (fresh peer)(RunTime): 5505.728635682159 us | 5.5057 ms | 0.005506 s
Import + resolve nested tree with 200 leaves (fresh peer)(RunTime): 26821.930434782607 us | 26.8219 ms | 0.026822 s
Import + resolve nested tree with 800 leaves (fresh peer)(RunTime): 121638.6 us | 121.6386 ms | 0.121639 s
OpIdKey view x100k(RunTime): 4743.71011235955 us | 4.7437 ms | 0.004744 s
OpIdKey hashCode x100k (cold)(RunTime): 19601.087378640776 us | 19.6011 ms | 0.019601 s
OpIdKey map lookup x10k(RunTime): 552.14225 us | 0.5521 ms | 0.000552 s
OperationId map lookup x10k(RunTime): 349.91846652267816 us | 0.3499 ms | 0.000350 s
CRDTORSetHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 29976.90625 us | 29.9769 ms | 0.029977 s
PeerId generate x100(RunTime): 1612.0037481259371 us | 1.6120 ms | 0.001612 s
PeerId toUint8List x1000(RunTime): 317.67591706539076 us | 0.3177 ms | 0.000318 s
PeerId fromUint8List x1000(RunTime): 582.38 us | 0.5824 ms | 0.000582 s
Fugue text remote keystroke + read on 2000 chars(RunTime): 61.945 us | 0.0619 ms | 0.000062 s
Fugue text remote keystroke + read on 10000 chars(RunTime): 190.09 us | 0.1901 ms | 0.000190 s
Fugue text remote keystroke + read on 30000 chars(RunTime): 744.18 us | 0.7442 ms | 0.000744 s
Text remote keystroke + read on 2000 chars(RunTime): 9.14 us | 0.0091 ms | 0.000009 s
Text remote keystroke + read on 10000 chars(RunTime): 12.175 us | 0.0122 ms | 0.000012 s
Text remote keystroke + read on 30000 chars(RunTime): 26.16 us | 0.0262 ms | 0.000026 s
Map remote set + read on 1000 keys(RunTime): 9.245 us | 0.0092 ms | 0.000009 s
Map remote set + read on 5000 keys(RunTime): 4.905 us | 0.0049 ms | 0.000005 s
OR-set remote add from the past + read on 1000 values(RunTime): 30.43 us | 0.0304 ms | 0.000030 s
OR-set remote add from the past + read on 5000 values(RunTime): 116.46 us | 0.1165 ms | 0.000116 s
OR-map remote put from the past + read on 1000 keys(RunTime): 65.6 us | 0.0656 ms | 0.000066 s
OR-map remote put from the past + read on 5000 keys(RunTime): 250.39 us | 0.2504 ms | 0.000250 s
Import 1000 chained changes(RunTime): 9285.919540229885 us | 9.2859 ms | 0.009286 s
Import 10000 chained changes(RunTime): 120057.27272727272 us | 120.0573 ms | 0.120057 s
exportChangesNewerThan on 50000 changes / 10 peers (99% caught-up)(RunTime): 15.414607116009083 us | 0.0154 ms | 0.000015 s
takeSnapshot(pruneHistory) with 10000 changes(RunTime): 243660.0 us | 243.6600 ms | 0.243660 s
takeSnapshot(pruneHistory) with 100 concurrent heads(RunTime): 39884.47169811321 us | 39.8845 ms | 0.039884 s
Binary encode/decode 1000 changes(RunTime): 23708.697247706423 us | 23.7087 ms | 0.023709 s
Take snapshot with 1000 changes(RunTime): 1280.747 us | 1.2807 ms | 0.001281 s
CRDTTextHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 29290.511904761905 us | 29.2905 ms | 0.029291 s
CRDTTextHandler do 1000 operations and get value (incremental cache update: false)(RunTime): 28716.708860759492 us | 28.7167 ms | 0.028717 s
Import 1000 concurrent changes(RunTime): 9497.586387434554 us | 9.4976 ms | 0.009498 s
VersionVector toBytes 10 peers x1000(RunTime): 4250.966 us | 4.2510 ms | 0.004251 s
VersionVector fromBytes 10 peers x1000(RunTime): 13953.636363636364 us | 13.9536 ms | 0.013954 s
VersionVector intersection 10 peers x1000(RunTime): 1836.7556221889056 us | 1.8368 ms | 0.001837 s
