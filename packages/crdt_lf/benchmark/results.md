Apply 1000 changes(RunTime): 9254.930735930737 us | 9.2549 ms | 0.009255 s
Change toBytes x1000(RunTime): 591.2955 us | 0.5913 ms | 0.000591 s
Change fromBytes x1000(RunTime): 184.96260723610592 us | 0.1850 ms | 0.000185 s
Change roundtrip x1000(RunTime): 785.13825 us | 0.7851 ms | 0.000785 s
DAG addNode chain of 1000(RunTime): 1789.416791604198 us | 1.7894 ms | 0.001789 s
DAG getAncestors chain of 200(RunTime): 75.19087261409233 us | 0.0752 ms | 0.000075 s
CRDTFugueListHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 32500.145161290322 us | 32.5001 ms | 0.032500 s
HLC toUint8List x100k(RunTime): 238.181170983184 us | 0.2382 ms | 0.000238 s
HLC fromUint8List x100k(RunTime): 5057.545 us | 5.0575 ms | 0.005058 s
HLC compareTo x100k(RunTime): 448.04745011086476 us | 0.4480 ms | 0.000448 s
CRDTListHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 24808.9625 us | 24.8090 ms | 0.024809 s
CRDTMapHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 24684.219512195123 us | 24.6842 ms | 0.024684 s
Resolve nested tree with 50 leaves (cold caches)(RunTime): 2026.932 us | 2.0269 ms | 0.002027 s
Resolve nested tree with 200 leaves (cold caches)(RunTime): 8860.946188340808 us | 8.8609 ms | 0.008861 s
Resolve nested tree with 800 leaves (cold caches)(RunTime): 40290.730769230766 us | 40.2907 ms | 0.040291 s
Import + resolve nested tree with 50 leaves (fresh peer)(RunTime): 5566.734831460674 us | 5.5667 ms | 0.005567 s
Import + resolve nested tree with 200 leaves (fresh peer)(RunTime): 22592.13913043478 us | 22.5921 ms | 0.022592 s
Import + resolve nested tree with 800 leaves (fresh peer)(RunTime): 106800.8947368421 us | 106.8009 ms | 0.106801 s
OpIdKey view x100k(RunTime): 4794.377528089888 us | 4.7944 ms | 0.004794 s
OpIdKey hashCode x100k (cold)(RunTime): 19643.834951456312 us | 19.6438 ms | 0.019644 s
OpIdKey map lookup x10k(RunTime): 539.279 us | 0.5393 ms | 0.000539 s
OperationId map lookup x10k(RunTime): 357.4818067754078 us | 0.3575 ms | 0.000357 s
CRDTORSetHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 28451.60606060606 us | 28.4516 ms | 0.028452 s
PeerId generate x100(RunTime): 1621.730884557721 us | 1.6217 ms | 0.001622 s
PeerId toUint8List x1000(RunTime): 320.42066601371204 us | 0.3204 ms | 0.000320 s
PeerId fromUint8List x1000(RunTime): 579.374 us | 0.5794 ms | 0.000579 s
Import 1000 chained changes(RunTime): 9632.969348659004 us | 9.6330 ms | 0.009633 s
Import 10000 chained changes(RunTime): 110866.72727272728 us | 110.8667 ms | 0.110867 s
exportChangesNewerThan on 50000 changes / 10 peers (99% caught-up)(RunTime): 15.810026779678644 us | 0.0158 ms | 0.000016 s
takeSnapshot(pruneHistory) with 10000 changes(RunTime): 255813.9 us | 255.8139 ms | 0.255814 s
takeSnapshot(pruneHistory) with 100 concurrent heads(RunTime): 37732.38888888889 us | 37.7324 ms | 0.037732 s
Binary encode/decode 1000 changes(RunTime): 23891.56862745098 us | 23.8916 ms | 0.023892 s
Take snapshot with 1000 changes(RunTime): 1296.6635 us | 1.2967 ms | 0.001297 s
CRDTTextHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 25676.78787878788 us | 25.6768 ms | 0.025677 s
CRDTTextHandler do 1000 operations and get value (incremental cache update: false)(RunTime): 27069.753246753247 us | 27.0698 ms | 0.027070 s
Import 1000 concurrent changes(RunTime): 9465.921465968586 us | 9.4659 ms | 0.009466 s
VersionVector toBytes 10 peers x1000(RunTime): 4435.912 us | 4.4359 ms | 0.004436 s
VersionVector fromBytes 10 peers x1000(RunTime): 14167.531468531468 us | 14.1675 ms | 0.014168 s
VersionVector intersection 10 peers x1000(RunTime): 1839.6469265367316 us | 1.8396 ms | 0.001840 s
