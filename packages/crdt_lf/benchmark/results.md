Apply 1000 changes(RunTime): 9309.1327014218 us | 9.3091 ms | 0.009309 s
Change toBytes x1000(RunTime): 592.65125 us | 0.5927 ms | 0.000593 s
Change fromBytes x1000(RunTime): 190.08460445286593 us | 0.1901 ms | 0.000190 s
Change roundtrip x1000(RunTime): 795.23725 us | 0.7952 ms | 0.000795 s
DAG addNode chain of 1000(RunTime): 1842.856071964018 us | 1.8429 ms | 0.001843 s
DAG getAncestors chain of 200(RunTime): 74.87966274910578 us | 0.0749 ms | 0.000075 s
CRDTFugueListHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 33023.269841269845 us | 33.0233 ms | 0.033023 s
HLC toUint8List x100k(RunTime): 251.1408253968254 us | 0.2511 ms | 0.000251 s
HLC fromUint8List x100k(RunTime): 5139.675 us | 5.1397 ms | 0.005140 s
HLC compareTo x100k(RunTime): 451.21677852348995 us | 0.4512 ms | 0.000451 s
CRDTListHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 25733.03947368421 us | 25.7330 ms | 0.025733 s
CRDTMapHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 25483.25316455696 us | 25.4833 ms | 0.025483 s
Resolve nested tree with 50 leaves (cold caches)(RunTime): 2026.866 us | 2.0269 ms | 0.002027 s
Resolve nested tree with 200 leaves (cold caches)(RunTime): 8812.139830508475 us | 8.8121 ms | 0.008812 s
Resolve nested tree with 800 leaves (cold caches)(RunTime): 39442.78846153846 us | 39.4428 ms | 0.039443 s
Import + resolve nested tree with 50 leaves (fresh peer)(RunTime): 5408.733133433283 us | 5.4087 ms | 0.005409 s
Import + resolve nested tree with 200 leaves (fresh peer)(RunTime): 23870.284090909092 us | 23.8703 ms | 0.023870 s
Import + resolve nested tree with 800 leaves (fresh peer)(RunTime): 146568.60869565216 us | 146.5686 ms | 0.146569 s
OpIdKey view x100k(RunTime): 4776.875 us | 4.7769 ms | 0.004777 s
OpIdKey hashCode x100k (cold)(RunTime): 20051.300970873788 us | 20.0513 ms | 0.020051 s
OpIdKey map lookup x10k(RunTime): 540.90725 us | 0.5409 ms | 0.000541 s
OperationId map lookup x10k(RunTime): 362.4340853013747 us | 0.3624 ms | 0.000362 s
CRDTORSetHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 29043.093333333334 us | 29.0431 ms | 0.029043 s
PeerId generate x100(RunTime): 1765.8335832083958 us | 1.7658 ms | 0.001766 s
PeerId toUint8List x1000(RunTime): 327.6279740447008 us | 0.3276 ms | 0.000328 s
PeerId fromUint8List x1000(RunTime): 586.0915 us | 0.5861 ms | 0.000586 s
Import 1000 chained changes(RunTime): 9819.322097378277 us | 9.8193 ms | 0.009819 s
Import 10000 chained changes(RunTime): 115369.6875 us | 115.3697 ms | 0.115370 s
exportChangesNewerThan on 50000 changes / 10 peers (99% caught-up)(RunTime): 29.821819623631317 us | 0.0298 ms | 0.000030 s
takeSnapshot(pruneHistory) with 10000 changes(RunTime): 244280.75 us | 244.2808 ms | 0.244281 s
takeSnapshot(pruneHistory) with 100 concurrent heads(RunTime): 38395.57692307692 us | 38.3956 ms | 0.038396 s
Binary encode/decode 1000 changes(RunTime): 23728.354166666668 us | 23.7284 ms | 0.023728 s
Take snapshot with 1000 changes(RunTime): 1289.0925 us | 1.2891 ms | 0.001289 s
CRDTTextHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 28339.060606060608 us | 28.3391 ms | 0.028339 s
CRDTTextHandler do 1000 operations and get value (incremental cache update: false)(RunTime): 27635.247191011236 us | 27.6352 ms | 0.027635 s
Import 1000 concurrent changes(RunTime): 9505.51282051282 us | 9.5055 ms | 0.009506 s
VersionVector toBytes 10 peers x1000(RunTime): 4478.268 us | 4.4783 ms | 0.004478 s
VersionVector fromBytes 10 peers x1000(RunTime): 14681.753623188406 us | 14.6818 ms | 0.014682 s
VersionVector intersection 10 peers x1000(RunTime): 1858.8665667166417 us | 1.8589 ms | 0.001859 s
