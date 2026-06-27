Apply 1000 changes(RunTime): 9685.965517241379 us | 9.6860 ms | 0.009686 s
Change toBytes x1000(RunTime): 594.19875 us | 0.5942 ms | 0.000594 s
Change fromBytes x1000(RunTime): 190.53661771672193 us | 0.1905 ms | 0.000191 s
Change roundtrip x1000(RunTime): 875.84875 us | 0.8758 ms | 0.000876 s
DAG addNode chain of 1000(RunTime): 1883.2218890554723 us | 1.8832 ms | 0.001883 s
DAG getAncestors chain of 200(RunTime): 76.86023235732789 us | 0.0769 ms | 0.000077 s
CRDTFugueListHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 35061.4 us | 35.0614 ms | 0.035061 s
HLC toUint8List x100k(RunTime): 250.887375 us | 0.2509 ms | 0.000251 s
HLC fromUint8List x100k(RunTime): 5017.310112359551 us | 5.0173 ms | 0.005017 s
HLC compareTo x100k(RunTime): 451.0599163957269 us | 0.4511 ms | 0.000451 s
CRDTListHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 25340.506329113923 us | 25.3405 ms | 0.025341 s
CRDTMapHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 25426.151898734177 us | 25.4262 ms | 0.025426 s
Resolve nested tree with 50 leaves (cold caches)(RunTime): 1894.807 us | 1.8948 ms | 0.001895 s
Resolve nested tree with 200 leaves (cold caches)(RunTime): 8325.14 us | 8.3251 ms | 0.008325 s
Resolve nested tree with 800 leaves (cold caches)(RunTime): 38893.480769230766 us | 38.8935 ms | 0.038893 s
Import + resolve nested tree with 50 leaves (fresh peer)(RunTime): 5433.335497835498 us | 5.4333 ms | 0.005433 s
Import + resolve nested tree with 200 leaves (fresh peer)(RunTime): 29334.669811320753 us | 29.3347 ms | 0.029335 s
Import + resolve nested tree with 800 leaves (fresh peer)(RunTime): 134442.96 us | 134.4430 ms | 0.134443 s
OpIdKey view x100k(RunTime): 5104.36404494382 us | 5.1044 ms | 0.005104 s
OpIdKey hashCode x100k (cold)(RunTime): 20273.962962962964 us | 20.2740 ms | 0.020274 s
OpIdKey map lookup x10k(RunTime): 537.883 us | 0.5379 ms | 0.000538 s
OperationId map lookup x10k(RunTime): 358.6677923924636 us | 0.3587 ms | 0.000359 s
CRDTORSetHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 28459.969696969696 us | 28.4600 ms | 0.028460 s
PeerId generate x100(RunTime): 1622.3950524737631 us | 1.6224 ms | 0.001622 s
PeerId toUint8List x1000(RunTime): 316.81353503184715 us | 0.3168 ms | 0.000317 s
PeerId fromUint8List x1000(RunTime): 585.91025 us | 0.5859 ms | 0.000586 s
Import 1000 chained changes(RunTime): 9095.4181184669 us | 9.0954 ms | 0.009095 s
Import 10000 chained changes(RunTime): 121366.84210526316 us | 121.3668 ms | 0.121367 s
exportChangesNewerThan on 50000 changes / 10 peers (99% caught-up)(RunTime): 19.62884342789143 us | 0.0196 ms | 0.000020 s
takeSnapshot(pruneHistory) with 10000 changes(RunTime): 317799.6666666667 us | 317.7997 ms | 0.317800 s
takeSnapshot(pruneHistory) with 100 concurrent heads(RunTime): 37989.96296296296 us | 37.9900 ms | 0.037990 s
Binary encode/decode 1000 changes(RunTime): 24115.21568627451 us | 24.1152 ms | 0.024115 s
Take snapshot with 1000 changes(RunTime): 1281.4365 us | 1.2814 ms | 0.001281 s
CRDTTextHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 26564.155844155845 us | 26.5642 ms | 0.026564 s
CRDTTextHandler do 1000 operations and get value (incremental cache update: false)(RunTime): 28638.91011235955 us | 28.6389 ms | 0.028639 s
Import 1000 concurrent changes(RunTime): 9527.749003984063 us | 9.5277 ms | 0.009528 s
VersionVector toBytes 10 peers x1000(RunTime): 4283.304 us | 4.2833 ms | 0.004283 s
VersionVector fromBytes 10 peers x1000(RunTime): 14467.666666666666 us | 14.4677 ms | 0.014468 s
VersionVector intersection 10 peers x1000(RunTime): 1867.1821589205397 us | 1.8672 ms | 0.001867 s
