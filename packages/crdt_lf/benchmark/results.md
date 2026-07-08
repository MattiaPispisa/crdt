Apply 1000 changes(RunTime): 9676.846153846154 us | 9.6768 ms | 0.009677 s
Change toBytes x1000(RunTime): 594.12925 us | 0.5941 ms | 0.000594 s
Change fromBytes x1000(RunTime): 187.33245605790017 us | 0.1873 ms | 0.000187 s
Change roundtrip x1000(RunTime): 789.2845 us | 0.7893 ms | 0.000789 s
DAG addNode chain of 1000(RunTime): 1814.9175412293853 us | 1.8149 ms | 0.001815 s
DAG getAncestors chain of 200(RunTime): 73.80349858513101 us | 0.0738 ms | 0.000074 s
CRDTFugueListHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 35343.5 us | 35.3435 ms | 0.035343 s
HLC toUint8List x100k(RunTime): 244.27790655117727 us | 0.2443 ms | 0.000244 s
HLC fromUint8List x100k(RunTime): 5028.1825 us | 5.0282 ms | 0.005028 s
HLC compareTo x100k(RunTime): 451.15543113101904 us | 0.4512 ms | 0.000451 s
CRDTListHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 24987.0375 us | 24.9870 ms | 0.024987 s
CRDTMapHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 26422.8125 us | 26.4228 ms | 0.026423 s
Resolve nested tree with 50 leaves (cold caches)(RunTime): 1864.1521739130435 us | 1.8642 ms | 0.001864 s
Resolve nested tree with 200 leaves (cold caches)(RunTime): 8210.128 us | 8.2101 ms | 0.008210 s
Resolve nested tree with 800 leaves (cold caches)(RunTime): 38633.019230769234 us | 38.6330 ms | 0.038633 s
Import + resolve nested tree with 50 leaves (fresh peer)(RunTime): 5343.430735930736 us | 5.3434 ms | 0.005343 s
Import + resolve nested tree with 200 leaves (fresh peer)(RunTime): 29897.495327102803 us | 29.8975 ms | 0.029897 s
Import + resolve nested tree with 800 leaves (fresh peer)(RunTime): 140651.60869565216 us | 140.6516 ms | 0.140652 s
OpIdKey view x100k(RunTime): 4725.8 us | 4.7258 ms | 0.004726 s
OpIdKey hashCode x100k (cold)(RunTime): 19738.533980582524 us | 19.7385 ms | 0.019739 s
OpIdKey map lookup x10k(RunTime): 543.91475 us | 0.5439 ms | 0.000544 s
OperationId map lookup x10k(RunTime): 352.97634483967056 us | 0.3530 ms | 0.000353 s
CRDTORSetHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 28808.575757575756 us | 28.8086 ms | 0.028809 s
PeerId generate x100(RunTime): 1611.9970014992505 us | 1.6120 ms | 0.001612 s
PeerId toUint8List x1000(RunTime): 323.57997420187036 us | 0.3236 ms | 0.000324 s
PeerId fromUint8List x1000(RunTime): 593.84725 us | 0.5938 ms | 0.000594 s
Import 1000 chained changes(RunTime): 9602.725099601594 us | 9.6027 ms | 0.009603 s
Import 10000 chained changes(RunTime): 121774.18181818182 us | 121.7742 ms | 0.121774 s
exportChangesNewerThan on 50000 changes / 10 peers (99% caught-up)(RunTime): 15.737106011640433 us | 0.0157 ms | 0.000016 s
takeSnapshot(pruneHistory) with 10000 changes(RunTime): 249356.9 us | 249.3569 ms | 0.249357 s
takeSnapshot(pruneHistory) with 100 concurrent heads(RunTime): 37428.84905660377 us | 37.4288 ms | 0.037429 s
Binary encode/decode 1000 changes(RunTime): 23946.203703703704 us | 23.9462 ms | 0.023946 s
Take snapshot with 1000 changes(RunTime): 1281.426 us | 1.2814 ms | 0.001281 s
CRDTTextHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 26072.072916666668 us | 26.0721 ms | 0.026072 s
CRDTTextHandler do 1000 operations and get value (incremental cache update: false)(RunTime): 28764.20224719101 us | 28.7642 ms | 0.028764 s
Import 1000 concurrent changes(RunTime): 9908.69696969697 us | 9.9087 ms | 0.009909 s
VersionVector toBytes 10 peers x1000(RunTime): 4396.678 us | 4.3967 ms | 0.004397 s
VersionVector fromBytes 10 peers x1000(RunTime): 14105.132867132867 us | 14.1051 ms | 0.014105 s
VersionVector intersection 10 peers x1000(RunTime): 1878.0269865067467 us | 1.8780 ms | 0.001878 s
