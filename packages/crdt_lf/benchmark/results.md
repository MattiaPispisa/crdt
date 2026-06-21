Apply 1000 changes(RunTime): 9912.855 us | 9.9129 ms | 0.009913 s
Change toBytes x1000(RunTime): 591.45625 us | 0.5915 ms | 0.000591 s
Change fromBytes x1000(RunTime): 186.07049608355092 us | 0.1861 ms | 0.000186 s
Change roundtrip x1000(RunTime): 777.58575 us | 0.7776 ms | 0.000778 s
DAG addNode chain of 1000(RunTime): 1746.0037481259371 us | 1.7460 ms | 0.001746 s
DAG getAncestors chain of 200(RunTime): 76.02058724265947 us | 0.0760 ms | 0.000076 s
CRDTFugueListHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 120110.29411764706 us | 120.1103 ms | 0.120110 s
HLC toUint8List x100k(RunTime): 239.25422667501564 us | 0.2393 ms | 0.000239 s
HLC fromUint8List x100k(RunTime): 5031.3475 us | 5.0313 ms | 0.005031 s
HLC compareTo x100k(RunTime): 449.40555555555557 us | 0.4494 ms | 0.000449 s
CRDTListHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 26549.8625 us | 26.5499 ms | 0.026550 s
CRDTMapHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 25383.556962025315 us | 25.3836 ms | 0.025384 s
Resolve nested tree with 50 leaves (cold caches)(RunTime): 1574.56071964018 us | 1.5746 ms | 0.001575 s
Resolve nested tree with 200 leaves (cold caches)(RunTime): 6760.685064935065 us | 6.7607 ms | 0.006761 s
Resolve nested tree with 800 leaves (cold caches)(RunTime): 31985.6875 us | 31.9857 ms | 0.031986 s
Import + resolve nested tree with 50 leaves (fresh peer)(RunTime): 4897.62 us | 4.8976 ms | 0.004898 s
Import + resolve nested tree with 200 leaves (fresh peer)(RunTime): 26446.981981981982 us | 26.4470 ms | 0.026447 s
Import + resolve nested tree with 800 leaves (fresh peer)(RunTime): 124667.75 us | 124.6677 ms | 0.124668 s
OpIdKey view x100k(RunTime): 4737.004494382022 us | 4.7370 ms | 0.004737 s
OpIdKey hashCode x100k (cold)(RunTime): 19445.443396226416 us | 19.4454 ms | 0.019445 s
OpIdKey map lookup x10k(RunTime): 549.2895 us | 0.5493 ms | 0.000549 s
OperationId map lookup x10k(RunTime): 357.90638983354216 us | 0.3579 ms | 0.000358 s
CRDTORSetHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 28668.436619718308 us | 28.6684 ms | 0.028668 s
PeerId generate x100(RunTime): 1619.6731634182909 us | 1.6197 ms | 0.001620 s
PeerId toUint8List x1000(RunTime): 321.60398089171974 us | 0.3216 ms | 0.000322 s
PeerId fromUint8List x1000(RunTime): 582.0485 us | 0.5820 ms | 0.000582 s
Import 1000 chained changes(RunTime): 9496.733333333334 us | 9.4967 ms | 0.009497 s
Import 10000 chained changes(RunTime): 113164.27272727272 us | 113.1643 ms | 0.113164 s
exportChangesNewerThan on 50000 changes / 10 peers (99% caught-up)(RunTime): 15.347315763421182 us | 0.0153 ms | 0.000015 s
takeSnapshot(pruneHistory) with 10000 changes(RunTime): 238374.6 us | 238.3746 ms | 0.238375 s
takeSnapshot(pruneHistory) with 100 concurrent heads(RunTime): 37809.16981132075 us | 37.8092 ms | 0.037809 s
Binary encode/decode 1000 changes(RunTime): 25104.340425531915 us | 25.1043 ms | 0.025104 s
Take snapshot with 1000 changes(RunTime): 1262.3575 us | 1.2624 ms | 0.001262 s
CRDTTextHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 26169.71875 us | 26.1697 ms | 0.026170 s
CRDTTextHandler do 1000 operations and get value (incremental cache update: false)(RunTime): 28544.075757575756 us | 28.5441 ms | 0.028544 s
Import 1000 concurrent changes(RunTime): 9495.099526066351 us | 9.4951 ms | 0.009495 s
VersionVector toBytes 10 peers x1000(RunTime): 4269.02 us | 4.2690 ms | 0.004269 s
VersionVector fromBytes 10 peers x1000(RunTime): 14120.055944055945 us | 14.1201 ms | 0.014120 s
VersionVector intersection 10 peers x1000(RunTime): 1921.3575712143927 us | 1.9214 ms | 0.001921 s
