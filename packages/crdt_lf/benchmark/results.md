Apply 1000 changes(RunTime): 9357.245421245421 us | 9.3572 ms | 0.009357 s
Change toBytes x1000(RunTime): 596.7115 us | 0.5967 ms | 0.000597 s
Change fromBytes x1000(RunTime): 188.18607295120796 us | 0.1882 ms | 0.000188 s
Change roundtrip x1000(RunTime): 787.5115 us | 0.7875 ms | 0.000788 s
DAG addNode chain of 1000(RunTime): 1845.7076461769116 us | 1.8457 ms | 0.001846 s
DAG getAncestors chain of 200(RunTime): 77.49597203222375 us | 0.0775 ms | 0.000077 s
CRDTFugueListHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 33087.77272727273 us | 33.0878 ms | 0.033088 s
HLC toUint8List x100k(RunTime): 254.5053431183211 us | 0.2545 ms | 0.000255 s
HLC fromUint8List x100k(RunTime): 5088.829213483146 us | 5.0888 ms | 0.005089 s
HLC compareTo x100k(RunTime): 540.6219977553311 us | 0.5406 ms | 0.000541 s
CRDTListHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 26524.467532467534 us | 26.5245 ms | 0.026524 s
CRDTMapHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 26959.76388888889 us | 26.9598 ms | 0.026960 s
Resolve nested tree with 50 leaves (cold caches)(RunTime): 2179.023 us | 2.1790 ms | 0.002179 s
Resolve nested tree with 200 leaves (cold caches)(RunTime): 9121.627802690584 us | 9.1216 ms | 0.009122 s
Resolve nested tree with 800 leaves (cold caches)(RunTime): 41436.42857142857 us | 41.4364 ms | 0.041436 s
Import + resolve nested tree with 50 leaves (fresh peer)(RunTime): 5493.966292134832 us | 5.4940 ms | 0.005494 s
Import + resolve nested tree with 200 leaves (fresh peer)(RunTime): 23805.537735849055 us | 23.8055 ms | 0.023806 s
Import + resolve nested tree with 800 leaves (fresh peer)(RunTime): 117710.45833333333 us | 117.7105 ms | 0.117710 s
OpIdKey view x100k(RunTime): 4795.384269662922 us | 4.7954 ms | 0.004795 s
OpIdKey hashCode x100k (cold)(RunTime): 20079.85436893204 us | 20.0799 ms | 0.020080 s
OpIdKey map lookup x10k(RunTime): 562.68875 us | 0.5627 ms | 0.000563 s
OperationId map lookup x10k(RunTime): 596.2135 us | 0.5962 ms | 0.000596 s
CRDTORSetHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 30097.582089552237 us | 30.0976 ms | 0.030098 s
PeerId generate x100(RunTime): 1620.2548725637182 us | 1.6203 ms | 0.001620 s
PeerId toUint8List x1000(RunTime): 319.25248 us | 0.3193 ms | 0.000319 s
PeerId fromUint8List x1000(RunTime): 579.20525 us | 0.5792 ms | 0.000579 s
Import 1000 chained changes(RunTime): 9607.924302788844 us | 9.6079 ms | 0.009608 s
Import 10000 chained changes(RunTime): 136858.86956521738 us | 136.8589 ms | 0.136859 s
exportChangesNewerThan on 50000 changes / 10 peers (99% caught-up)(RunTime): 15.387245563772181 us | 0.0154 ms | 0.000015 s
takeSnapshot(pruneHistory) with 10000 changes(RunTime): 248432.6 us | 248.4326 ms | 0.248433 s
takeSnapshot(pruneHistory) with 100 concurrent heads(RunTime): 37435.018867924526 us | 37.4350 ms | 0.037435 s
Binary encode/decode 1000 changes(RunTime): 24388.727272727272 us | 24.3887 ms | 0.024389 s
Take snapshot with 1000 changes(RunTime): 1302.9785 us | 1.3030 ms | 0.001303 s
CRDTTextHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 27922.466666666667 us | 27.9225 ms | 0.027922 s
CRDTTextHandler do 1000 operations and get value (incremental cache update: false)(RunTime): 29587.464285714286 us | 29.5875 ms | 0.029587 s
Import 1000 concurrent changes(RunTime): 9554.956 us | 9.5550 ms | 0.009555 s
VersionVector toBytes 10 peers x1000(RunTime): 4361.954 us | 4.3620 ms | 0.004362 s
VersionVector fromBytes 10 peers x1000(RunTime): 14413.391608391608 us | 14.4134 ms | 0.014413 s
VersionVector intersection 10 peers x1000(RunTime): 1874.2946026986506 us | 1.8743 ms | 0.001874 s
