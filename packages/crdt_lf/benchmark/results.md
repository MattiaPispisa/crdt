Apply 1000 changes(RunTime): 9625.854406130267 us | 9.6259 ms | 0.009626 s
Change toBytes x1000(RunTime): 584.2195 us | 0.5842 ms | 0.000584 s
Change fromBytes x1000(RunTime): 185.08260105448156 us | 0.1851 ms | 0.000185 s
Change roundtrip x1000(RunTime): 777.29775 us | 0.7773 ms | 0.000777 s
DAG addNode chain of 1000(RunTime): 1782.027736131934 us | 1.7820 ms | 0.001782 s
DAG getAncestors chain of 200(RunTime): 75.87909101204183 us | 0.0759 ms | 0.000076 s
HLC toUint8List x100k(RunTime): 241.9244845675247 us | 0.2419 ms | 0.000242 s
HLC fromUint8List x100k(RunTime): 5222.74 us | 5.2227 ms | 0.005223 s
HLC compareTo x100k(RunTime): 449.52935883014624 us | 0.4495 ms | 0.000450 s
CRDTListHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 24252.01219512195 us | 24.2520 ms | 0.024252 s
CRDTMapHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 24459.146341463416 us | 24.4591 ms | 0.024459 s
OpIdKey view x100k(RunTime): 4730.959550561798 us | 4.7310 ms | 0.004731 s
OpIdKey hashCode x100k (cold)(RunTime): 19380.26213592233 us | 19.3803 ms | 0.019380 s
OpIdKey map lookup x10k(RunTime): 541.85975 us | 0.5419 ms | 0.000542 s
OperationId map lookup x10k(RunTime): 349.5135798142632 us | 0.3495 ms | 0.000350 s
CRDTORSetHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 27190.07894736842 us | 27.1901 ms | 0.027190 s
PeerId generate x100(RunTime): 1607.7848575712144 us | 1.6078 ms | 0.001608 s
PeerId toUint8List x1000(RunTime): 316.7782677165354 us | 0.3168 ms | 0.000317 s
PeerId fromUint8List x1000(RunTime): 581.4715 us | 0.5815 ms | 0.000581 s
Import 1000 chained changes(RunTime): 9446.275 us | 9.4463 ms | 0.009446 s
Import 10000 chained changes(RunTime): 111340.94736842105 us | 111.3409 ms | 0.111341 s
exportChangesNewerThan on 50000 changes / 10 peers (99% caught-up)(RunTime): 15.448644920291708 us | 0.0154 ms | 0.000015 s
takeSnapshot(pruneHistory) with 10000 changes(RunTime): 217686.33333333334 us | 217.6863 ms | 0.217686 s
takeSnapshot(pruneHistory) with 100 concurrent heads(RunTime): 37634.30909090909 us | 37.6343 ms | 0.037634 s
Binary encode/decode 1000 changes(RunTime): 23866.00909090909 us | 23.8660 ms | 0.023866 s
Take snapshot with 1000 changes(RunTime): 1310.1645 us | 1.3102 ms | 0.001310 s
CRDTTextHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 25124.86274509804 us | 25.1249 ms | 0.025125 s
CRDTTextHandler do 1000 operations and get value (incremental cache update: false)(RunTime): 36556.620689655174 us | 36.5566 ms | 0.036557 s
Import 1000 concurrent changes(RunTime): 9644.812734082398 us | 9.6448 ms | 0.009645 s
VersionVector toBytes 10 peers x1000(RunTime): 4361.386 us | 4.3614 ms | 0.004361 s
VersionVector fromBytes 10 peers x1000(RunTime): 14439.840579710144 us | 14.4398 ms | 0.014440 s
VersionVector intersection 10 peers x1000(RunTime): 1890.4752623688155 us | 1.8905 ms | 0.001890 s
