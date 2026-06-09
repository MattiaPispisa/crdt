Apply 1000 changes(RunTime): 9210.505494505494 us | 9.2105 ms | 0.009211 s
Change toBytes x1000(RunTime): 574.89 us | 0.5749 ms | 0.000575 s
Change fromBytes x1000(RunTime): 2814.8475 us | 2.8148 ms | 0.002815 s
Change roundtrip x1000(RunTime): 3423.2293853073465 us | 3.4232 ms | 0.003423 s
DAG addNode chain of 1000(RunTime): 1717.8688155922039 us | 1.7179 ms | 0.001718 s
DAG getAncestors chain of 200(RunTime): 71.78693740392521 us | 0.0718 ms | 0.000072 s
HLC toUint8List x100k(RunTime): 244.18639328984156 us | 0.2442 ms | 0.000244 s
HLC fromUint8List x100k(RunTime): 4968.065 us | 4.9681 ms | 0.004968 s
HLC compareTo x100k(RunTime): 439.8151793525809 us | 0.4398 ms | 0.000440 s
OpIdKey view x100k(RunTime): 4622.1865168539325 us | 4.6222 ms | 0.004622 s
OpIdKey hashCode x100k (cold)(RunTime): 18771.091743119265 us | 18.7711 ms | 0.018771 s
OpIdKey map lookup x10k(RunTime): 532.99125 us | 0.5330 ms | 0.000533 s
OperationId map lookup x10k(RunTime): 349.76026443980516 us | 0.3498 ms | 0.000350 s
CRDTORSetHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 2493716.0 us | 2493.7160 ms | 2.493716 s
PeerId generate x100(RunTime): 1585.3575712143927 us | 1.5854 ms | 0.001585 s
PeerId toUint8List x1000(RunTime): 307.3296313435138 us | 0.3073 ms | 0.000307 s
PeerId fromUint8List x1000(RunTime): 577.47675 us | 0.5775 ms | 0.000577 s
Binary encode/decode 1000 changes(RunTime): 25315.380952380954 us | 25.3154 ms | 0.025315 s
Take snapshot with 1000 changes(RunTime): 15.232527622306645 us | 0.0152 ms | 0.000015 s
CRDTTextHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 1044157.0 us | 1044.1570 ms | 1.044157 s
CRDTTextHandler do 1000 operations and get value (incremental cache update: false)(RunTime): 1307386.5 us | 1307.3865 ms | 1.307387 s
Import 1000 concurrent changes(RunTime): 9595.390134529149 us | 9.5954 ms | 0.009595 s
VersionVector toBytes 10 peers x1000(RunTime): 4295.312 us | 4.2953 ms | 0.004295 s
VersionVector fromBytes 10 peers x1000(RunTime): 13922.302013422819 us | 13.9223 ms | 0.013922 s
VersionVector intersection 10 peers x1000(RunTime): 1869.7113943028485 us | 1.8697 ms | 0.001870 s
