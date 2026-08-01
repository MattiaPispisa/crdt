Apply 1000 changes(RunTime): 9656.670498084291 us | 9.6567 ms | 0.009657 s
Change toBytes x1000(RunTime): 599.225 us | 0.5992 ms | 0.000599 s
Change fromBytes x1000(RunTime): 191.14931312174326 us | 0.1911 ms | 0.000191 s
Change roundtrip x1000(RunTime): 802.78375 us | 0.8028 ms | 0.000803 s
DAG addNode chain of 1000(RunTime): 1830.553223388306 us | 1.8306 ms | 0.001831 s
DAG getAncestors chain of 200(RunTime): 72.3687450500396 us | 0.0724 ms | 0.000072 s
CRDTFugueListHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 33669.862068965514 us | 33.6699 ms | 0.033670 s
FugueTree append 50000 elements(RunTime): 305657.71428571426 us | 305.6577 ms | 0.305658 s
FugueTree prepend 50000 elements(RunTime): 750711.0 us | 750.7110 ms | 0.750711 s
FugueTree random insert 50000 elements(RunTime): 791553.6666666666 us | 791.5537 ms | 0.791554 s
FugueTree values() over 50000 live elements(RunTime): 8634.186119873817 us | 8.6342 ms | 0.008634 s
FugueTree values() over 50000 elements, 90% tombstones(RunTime): 1275.4995 us | 1.2755 ms | 0.001275 s
HLC toUint8List x100k(RunTime): 244.1358958462492 us | 0.2441 ms | 0.000244 s
HLC fromUint8List x100k(RunTime): 5132.665 us | 5.1327 ms | 0.005133 s
HLC compareTo x100k(RunTime): 451.4924107142857 us | 0.4515 ms | 0.000451 s
CRDTListHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 26024.88157894737 us | 26.0249 ms | 0.026025 s
CRDTMapHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 26732.402777777777 us | 26.7324 ms | 0.026732 s
Resolve nested tree with 50 leaves (cold caches)(RunTime): 1929.841 us | 1.9298 ms | 0.001930 s
Resolve nested tree with 200 leaves (cold caches)(RunTime): 8367.996 us | 8.3680 ms | 0.008368 s
Resolve nested tree with 800 leaves (cold caches)(RunTime): 34653.24137931035 us | 34.6532 ms | 0.034653 s
Import + resolve nested tree with 50 leaves (fresh peer)(RunTime): 5324.984269662921 us | 5.3250 ms | 0.005325 s
Import + resolve nested tree with 200 leaves (fresh peer)(RunTime): 23008.366071428572 us | 23.0084 ms | 0.023008 s
Import + resolve nested tree with 800 leaves (fresh peer)(RunTime): 94573.58333333333 us | 94.5736 ms | 0.094574 s
OpIdKey view x100k(RunTime): 4787.283146067416 us | 4.7873 ms | 0.004787 s
OpIdKey hashCode x100k (cold)(RunTime): 20211.543689320388 us | 20.2115 ms | 0.020212 s
OpIdKey map lookup x10k(RunTime): 539.1795 us | 0.5392 ms | 0.000539 s
OperationId map lookup x10k(RunTime): 379.18923418423975 us | 0.3792 ms | 0.000379 s
CRDTORSetHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 29824.573529411766 us | 29.8246 ms | 0.029825 s
PeerId generate x100(RunTime): 1637.035232383808 us | 1.6370 ms | 0.001637 s
PeerId toUint8List x1000(RunTime): 325.2571196094386 us | 0.3253 ms | 0.000325 s
PeerId fromUint8List x1000(RunTime): 596.267 us | 0.5963 ms | 0.000596 s
Import 1000 chained changes(RunTime): 9464.218009478673 us | 9.4642 ms | 0.009464 s
Import 10000 chained changes(RunTime): 114288.18181818182 us | 114.2882 ms | 0.114288 s
exportChangesNewerThan on 50000 changes / 10 peers (99% caught-up)(RunTime): 15.84526438972976 us | 0.0158 ms | 0.000016 s
takeSnapshot(pruneHistory) with 10000 changes(RunTime): 244164.88888888888 us | 244.1649 ms | 0.244165 s
takeSnapshot(pruneHistory) with 100 concurrent heads(RunTime): 38893.901960784315 us | 38.8939 ms | 0.038894 s
Binary encode/decode 1000 changes(RunTime): 23616.075471698114 us | 23.6161 ms | 0.023616 s
Take snapshot with 1000 changes(RunTime): 1315.182 us | 1.3152 ms | 0.001315 s
CRDTTextHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 29424.49295774648 us | 29.4245 ms | 0.029424 s
CRDTTextHandler do 1000 operations and get value (incremental cache update: false)(RunTime): 30718.869047619046 us | 30.7189 ms | 0.030719 s
Import 1000 concurrent changes(RunTime): 9943.106227106227 us | 9.9431 ms | 0.009943 s
VersionVector toBytes 10 peers x1000(RunTime): 4588.692134831461 us | 4.5887 ms | 0.004589 s
VersionVector fromBytes 10 peers x1000(RunTime): 14116.953020134228 us | 14.1170 ms | 0.014117 s
VersionVector intersection 10 peers x1000(RunTime): 1864.8185907046477 us | 1.8648 ms | 0.001865 s
