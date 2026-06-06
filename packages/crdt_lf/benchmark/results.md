Apply 1000 changes(RunTime): 9573.520179372197 us | 9.5735 ms | 0.009574 s
Change toBytes x1000(RunTime): 581.97125 us | 0.5820 ms | 0.000582 s
Change fromBytes x1000(RunTime): 2857.3475 us | 2.8573 ms | 0.002857 s
Change roundtrip x1000(RunTime): 3485.9220389805096 us | 3.4859 ms | 0.003486 s
DAG addNode chain of 1000(RunTime): 1770.391304347826 us | 1.7704 ms | 0.001770 s
DAG getAncestors chain of 200(RunTime): 70.95019599608008 us | 0.0710 ms | 0.000071 s
HLC toUint8List x100k(RunTime): 237.31905447564196 us | 0.2373 ms | 0.000237 s
HLC fromUint8List x100k(RunTime): 5197.8075 us | 5.1978 ms | 0.005198 s
HLC compareTo x100k(RunTime): 445.7057789496814 us | 0.4457 ms | 0.000446 s
OpIdKey view x100k(RunTime): 4767.87415730337 us | 4.7679 ms | 0.004768 s
OpIdKey hashCode x100k (cold)(RunTime): 19825.31 us | 19.8253 ms | 0.019825 s
OpIdKey map lookup x10k(RunTime): 544.143 us | 0.5441 ms | 0.000544 s
OperationId map lookup x10k(RunTime): 352.0789566443426 us | 0.3521 ms | 0.000352 s
CRDTORSetHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 2553016.5 us | 2553.0165 ms | 2.553017 s
PeerId generate x100(RunTime): 1634.994752623688 us | 1.6350 ms | 0.001635 s
PeerId toUint8List x1000(RunTime): 316.143207981581 us | 0.3161 ms | 0.000316 s
PeerId fromUint8List x1000(RunTime): 574.57925 us | 0.5746 ms | 0.000575 s
Binary encode/decode 1000 changes(RunTime): 25307.146788990827 us | 25.3071 ms | 0.025307 s
Take snapshot with 1000 changes(RunTime): 14.361218832687005 us | 0.0144 ms | 0.000014 s
CRDTTextHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 1011765.0 us | 1011.7650 ms | 1.011765 s
CRDTTextHandler do 1000 operations and get value (incremental cache update: false)(RunTime): 11632871.333333334 us | 11632.8713 ms | 11.632871 s
Import 1000 concurrent changes(RunTime): 10319.582375478927 us | 10.3196 ms | 0.010320 s
VersionVector toBytes 10 peers x1000(RunTime): 4344.442 us | 4.3444 ms | 0.004344 s
VersionVector fromBytes 10 peers x1000(RunTime): 13704.651006711409 us | 13.7047 ms | 0.013705 s
VersionVector intersection 10 peers x1000(RunTime): 1863.3950524737631 us | 1.8634 ms | 0.001863 s
