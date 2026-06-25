Apply 1000 changes(RunTime): 9384.703296703297 us | 9.3847 ms | 0.009385 s
Change toBytes x1000(RunTime): 595.97575 us | 0.5960 ms | 0.000596 s
Change fromBytes x1000(RunTime): 189.49144854956063 us | 0.1895 ms | 0.000189 s
Change roundtrip x1000(RunTime): 795.20925 us | 0.7952 ms | 0.000795 s
DAG addNode chain of 1000(RunTime): 1849.8133433283358 us | 1.8498 ms | 0.001850 s
DAG getAncestors chain of 200(RunTime): 73.13810591304987 us | 0.0731 ms | 0.000073 s
CRDTFugueListHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 32926.0625 us | 32.9261 ms | 0.032926 s
HLC toUint8List x100k(RunTime): 240.65122103944896 us | 0.2407 ms | 0.000241 s
HLC fromUint8List x100k(RunTime): 5006.076404494382 us | 5.0061 ms | 0.005006 s
HLC compareTo x100k(RunTime): 450.1791805094131 us | 0.4502 ms | 0.000450 s
CRDTListHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 25115.632911392404 us | 25.1156 ms | 0.025116 s
CRDTMapHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 24685.125 us | 24.6851 ms | 0.024685 s
Resolve nested tree with 50 leaves (cold caches)(RunTime): 2016.314 us | 2.0163 ms | 0.002016 s
Resolve nested tree with 200 leaves (cold caches)(RunTime): 8826.864406779661 us | 8.8269 ms | 0.008827 s
Resolve nested tree with 800 leaves (cold caches)(RunTime): 41466.4 us | 41.4664 ms | 0.041466 s
Import + resolve nested tree with 50 leaves (fresh peer)(RunTime): 5464.921348314607 us | 5.4649 ms | 0.005465 s
Import + resolve nested tree with 200 leaves (fresh peer)(RunTime): 22492.0 us | 22.4920 ms | 0.022492 s
Import + resolve nested tree with 800 leaves (fresh peer)(RunTime): 98827.85714285714 us | 98.8279 ms | 0.098828 s
OpIdKey view x100k(RunTime): 4804.148314606741 us | 4.8041 ms | 0.004804 s
OpIdKey hashCode x100k (cold)(RunTime): 19917.26213592233 us | 19.9173 ms | 0.019917 s
OpIdKey map lookup x10k(RunTime): 538.53275 us | 0.5385 ms | 0.000539 s
OperationId map lookup x10k(RunTime): 353.8362160254147 us | 0.3538 ms | 0.000354 s
CRDTORSetHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 28304.560606060608 us | 28.3046 ms | 0.028305 s
PeerId generate x100(RunTime): 1617.3590704647677 us | 1.6174 ms | 0.001617 s
PeerId toUint8List x1000(RunTime): 319.67083935162896 us | 0.3197 ms | 0.000320 s
PeerId fromUint8List x1000(RunTime): 580.764 us | 0.5808 ms | 0.000581 s
Import 1000 chained changes(RunTime): 9518.333333333334 us | 9.5183 ms | 0.009518 s
Import 10000 chained changes(RunTime): 118730.17391304347 us | 118.7302 ms | 0.118730 s
exportChangesNewerThan on 50000 changes / 10 peers (99% caught-up)(RunTime): 15.312268438657807 us | 0.0153 ms | 0.000015 s
takeSnapshot(pruneHistory) with 10000 changes(RunTime): 246015.0 us | 246.0150 ms | 0.246015 s
takeSnapshot(pruneHistory) with 100 concurrent heads(RunTime): 37936.943396226416 us | 37.9369 ms | 0.037937 s
Binary encode/decode 1000 changes(RunTime): 26336.893203883494 us | 26.3369 ms | 0.026337 s
Take snapshot with 1000 changes(RunTime): 1316.136 us | 1.3161 ms | 0.001316 s
CRDTTextHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 27083.463157894737 us | 27.0835 ms | 0.027083 s
CRDTTextHandler do 1000 operations and get value (incremental cache update: false)(RunTime): 27830.88732394366 us | 27.8309 ms | 0.027831 s
Import 1000 concurrent changes(RunTime): 9619.759581881533 us | 9.6198 ms | 0.009620 s
VersionVector toBytes 10 peers x1000(RunTime): 4267.298 us | 4.2673 ms | 0.004267 s
VersionVector fromBytes 10 peers x1000(RunTime): 14202.097902097903 us | 14.2021 ms | 0.014202 s
VersionVector intersection 10 peers x1000(RunTime): 1866.6386806596702 us | 1.8666 ms | 0.001867 s
