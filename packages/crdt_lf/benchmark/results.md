Apply 1000 changes(RunTime): 9889.589641434262 us | 9.8896 ms | 0.009890 s
Change toBytes x1000(RunTime): 595.506 us | 0.5955 ms | 0.000596 s
Change fromBytes x1000(RunTime): 189.49131227800711 us | 0.1895 ms | 0.000189 s
Change roundtrip x1000(RunTime): 796.038 us | 0.7960 ms | 0.000796 s
DAG addNode chain of 1000(RunTime): 1761.7398800599701 us | 1.7617 ms | 0.001762 s
DAG getAncestors chain of 200(RunTime): 72.9131714221858 us | 0.0729 ms | 0.000073 s
CRDTFugueListHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 33103.18309859155 us | 33.1032 ms | 0.033103 s
HLC toUint8List x100k(RunTime): 257.5753509752764 us | 0.2576 ms | 0.000258 s
HLC fromUint8List x100k(RunTime): 5009.62 us | 5.0096 ms | 0.005010 s
HLC compareTo x100k(RunTime): 461.9005574136009 us | 0.4619 ms | 0.000462 s
CRDTListHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 25673.963414634145 us | 25.6740 ms | 0.025674 s
CRDTMapHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 26152.213333333333 us | 26.1522 ms | 0.026152 s
Resolve nested tree with 50 leaves (cold caches)(RunTime): 1876.023988005997 us | 1.8760 ms | 0.001876 s
Resolve nested tree with 200 leaves (cold caches)(RunTime): 8231.044 us | 8.2310 ms | 0.008231 s
Resolve nested tree with 800 leaves (cold caches)(RunTime): 38811.17307692308 us | 38.8112 ms | 0.038811 s
Import + resolve nested tree with 50 leaves (fresh peer)(RunTime): 5364.392 us | 5.3644 ms | 0.005364 s
Import + resolve nested tree with 200 leaves (fresh peer)(RunTime): 28516.629213483146 us | 28.5166 ms | 0.028517 s
Import + resolve nested tree with 800 leaves (fresh peer)(RunTime): 119495.30769230769 us | 119.4953 ms | 0.119495 s
OpIdKey view x100k(RunTime): 4848.748314606742 us | 4.8487 ms | 0.004849 s
OpIdKey hashCode x100k (cold)(RunTime): 20024.6213592233 us | 20.0246 ms | 0.020025 s
OpIdKey map lookup x10k(RunTime): 532.6525 us | 0.5327 ms | 0.000533 s
OperationId map lookup x10k(RunTime): 350.09041527948136 us | 0.3501 ms | 0.000350 s
CRDTORSetHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 29188.166666666668 us | 29.1882 ms | 0.029188 s
PeerId generate x100(RunTime): 1632.2668665667165 us | 1.6323 ms | 0.001632 s
PeerId toUint8List x1000(RunTime): 322.9092228313447 us | 0.3229 ms | 0.000323 s
PeerId fromUint8List x1000(RunTime): 584.7085 us | 0.5847 ms | 0.000585 s
Import 1000 chained changes(RunTime): 9919.948207171316 us | 9.9199 ms | 0.009920 s
Import 10000 chained changes(RunTime): 128440.23809523809 us | 128.4402 ms | 0.128440 s
exportChangesNewerThan on 50000 changes / 10 peers (99% caught-up)(RunTime): 31.269825020080955 us | 0.0313 ms | 0.000031 s
takeSnapshot(pruneHistory) with 10000 changes(RunTime): 296234.3 us | 296.2343 ms | 0.296234 s
takeSnapshot(pruneHistory) with 100 concurrent heads(RunTime): 39980.442307692305 us | 39.9804 ms | 0.039980 s
Binary encode/decode 1000 changes(RunTime): 24089.947916666668 us | 24.0899 ms | 0.024090 s
Take snapshot with 1000 changes(RunTime): 1278.9215 us | 1.2789 ms | 0.001279 s
CRDTTextHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 26875.572916666668 us | 26.8756 ms | 0.026876 s
CRDTTextHandler do 1000 operations and get value (incremental cache update: false)(RunTime): 32590.51282051282 us | 32.5905 ms | 0.032591 s
Import 1000 concurrent changes(RunTime): 9889.16883116883 us | 9.8892 ms | 0.009889 s
VersionVector toBytes 10 peers x1000(RunTime): 4361.814 us | 4.3618 ms | 0.004362 s
VersionVector fromBytes 10 peers x1000(RunTime): 14499.463768115942 us | 14.4995 ms | 0.014499 s
VersionVector intersection 10 peers x1000(RunTime): 1793.9460269865067 us | 1.7939 ms | 0.001794 s
