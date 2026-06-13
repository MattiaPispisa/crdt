Apply 1000 changes(RunTime): 9443.309322033898 us | 9.4433 ms | 0.009443 s
Change toBytes x1000(RunTime): 591.0625 us | 0.5911 ms | 0.000591 s
Change fromBytes x1000(RunTime): 190.45699783814268 us | 0.1905 ms | 0.000190 s
Change roundtrip x1000(RunTime): 809.93775 us | 0.8099 ms | 0.000810 s
DAG addNode chain of 1000(RunTime): 1791.8815592203898 us | 1.7919 ms | 0.001792 s
DAG getAncestors chain of 200(RunTime): 73.74164859799346 us | 0.0737 ms | 0.000074 s
HLC toUint8List x100k(RunTime): 242.62127187577028 us | 0.2426 ms | 0.000243 s
HLC fromUint8List x100k(RunTime): 5016.1875 us | 5.0162 ms | 0.005016 s
HLC compareTo x100k(RunTime): 450.6328523862375 us | 0.4506 ms | 0.000451 s
CRDTListHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 24388.743902439026 us | 24.3887 ms | 0.024389 s
CRDTMapHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 24614.0375 us | 24.6140 ms | 0.024614 s
OpIdKey view x100k(RunTime): 4770.3056179775285 us | 4.7703 ms | 0.004770 s
OpIdKey hashCode x100k (cold)(RunTime): 18934.119266055044 us | 18.9341 ms | 0.018934 s
OpIdKey map lookup x10k(RunTime): 537.6145 us | 0.5376 ms | 0.000538 s
OperationId map lookup x10k(RunTime): 367.0668642341174 us | 0.3671 ms | 0.000367 s
CRDTORSetHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 27160.6 us | 27.1606 ms | 0.027161 s
PeerId generate x100(RunTime): 1610.304347826087 us | 1.6103 ms | 0.001610 s
PeerId toUint8List x1000(RunTime): 316.3120253164557 us | 0.3163 ms | 0.000316 s
PeerId fromUint8List x1000(RunTime): 576.1145 us | 0.5761 ms | 0.000576 s
Import 1000 chained changes(RunTime): 9915.011494252874 us | 9.9150 ms | 0.009915 s
Import 10000 chained changes(RunTime): 114286.63636363637 us | 114.2866 ms | 0.114287 s
exportChangesNewerThan on 50000 changes / 10 peers (99% caught-up)(RunTime): 15.67416017903483 us | 0.0157 ms | 0.000016 s
takeSnapshot(pruneHistory) with 10000 changes(RunTime): 233464.36363636365 us | 233.4644 ms | 0.233464 s
takeSnapshot(pruneHistory) with 100 concurrent heads(RunTime): 36594.46428571428 us | 36.5945 ms | 0.036594 s
Binary encode/decode 1000 changes(RunTime): 23842.29203539823 us | 23.8423 ms | 0.023842 s
Take snapshot with 1000 changes(RunTime): 1269.4525 us | 1.2695 ms | 0.001269 s
CRDTTextHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 25131.927083333332 us | 25.1319 ms | 0.025132 s
CRDTTextHandler do 1000 operations and get value (incremental cache update: false)(RunTime): 28698.232558139534 us | 28.6982 ms | 0.028698 s
Import 1000 concurrent changes(RunTime): 9349.791208791208 us | 9.3498 ms | 0.009350 s
VersionVector toBytes 10 peers x1000(RunTime): 4197.418 us | 4.1974 ms | 0.004197 s
VersionVector fromBytes 10 peers x1000(RunTime): 14304.055944055945 us | 14.3041 ms | 0.014304 s
VersionVector intersection 10 peers x1000(RunTime): 1806.6611694152923 us | 1.8067 ms | 0.001807 s
