Apply 1000 changes(RunTime): 9185.300366300366 us | 9.1853 ms | 0.009185 s
Change toBytes x1000(RunTime): 591.84525 us | 0.5918 ms | 0.000592 s
Change fromBytes x1000(RunTime): 189.39232871548393 us | 0.1894 ms | 0.000189 s
Change roundtrip x1000(RunTime): 786.07425 us | 0.7861 ms | 0.000786 s
DAG addNode chain of 1000(RunTime): 1800.128935532234 us | 1.8001 ms | 0.001800 s
DAG getAncestors chain of 200(RunTime): 75.65048507040127 us | 0.0757 ms | 0.000076 s
HLC toUint8List x100k(RunTime): 245.78907883409175 us | 0.2458 ms | 0.000246 s
HLC fromUint8List x100k(RunTime): 5036.0025 us | 5.0360 ms | 0.005036 s
HLC compareTo x100k(RunTime): 450.61915367483294 us | 0.4506 ms | 0.000451 s
OpIdKey view x100k(RunTime): 4717.503370786517 us | 4.7175 ms | 0.004718 s
OpIdKey hashCode x100k (cold)(RunTime): 18912.009433962263 us | 18.9120 ms | 0.018912 s
OpIdKey map lookup x10k(RunTime): 537.91875 us | 0.5379 ms | 0.000538 s
OperationId map lookup x10k(RunTime): 350.8456281759243 us | 0.3508 ms | 0.000351 s
CRDTORSetHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 2064135.5 us | 2064.1355 ms | 2.064135 s
PeerId generate x100(RunTime): 1620.4010494752624 us | 1.6204 ms | 0.001620 s
PeerId toUint8List x1000(RunTime): 315.53322834645667 us | 0.3155 ms | 0.000316 s
PeerId fromUint8List x1000(RunTime): 581.2115 us | 0.5812 ms | 0.000581 s
Binary encode/decode 1000 changes(RunTime): 24337.321428571428 us | 24.3373 ms | 0.024337 s
Take snapshot with 1000 changes(RunTime): 1379.854 us | 1.3799 ms | 0.001380 s
CRDTTextHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 1049158.0 us | 1049.1580 ms | 1.049158 s
CRDTTextHandler do 1000 operations and get value (incremental cache update: false)(RunTime): 1945336.5 us | 1945.3365 ms | 1.945337 s
Import 1000 concurrent changes(RunTime): 9482.561752988047 us | 9.4826 ms | 0.009483 s
VersionVector toBytes 10 peers x1000(RunTime): 4259.158 us | 4.2592 ms | 0.004259 s
VersionVector fromBytes 10 peers x1000(RunTime): 14332.426573426574 us | 14.3324 ms | 0.014332 s
VersionVector intersection 10 peers x1000(RunTime): 1818.269115442279 us | 1.8183 ms | 0.001818 s
