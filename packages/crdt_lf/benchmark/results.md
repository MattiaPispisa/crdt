Apply 1000 changes(RunTime): 9476.273542600897 us | 9.4763 ms | 0.009476 s
Change toBytes x1000(RunTime): 600.63125 us | 0.6006 ms | 0.000601 s
Change fromBytes x1000(RunTime): 192.686115355233 us | 0.1927 ms | 0.000193 s
Change roundtrip x1000(RunTime): 803.72675 us | 0.8037 ms | 0.000804 s
DAG addNode chain of 1000(RunTime): 1857.2046476761618 us | 1.8572 ms | 0.001857 s
DAG getAncestors chain of 200(RunTime): 76.02480816508977 us | 0.0760 ms | 0.000076 s
CRDTFugueListHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 34184.833333333336 us | 34.1848 ms | 0.034185 s
HLC toUint8List x100k(RunTime): 248.26552892458275 us | 0.2483 ms | 0.000248 s
HLC fromUint8List x100k(RunTime): 5032.26 us | 5.0323 ms | 0.005032 s
HLC compareTo x100k(RunTime): 460.58418541240627 us | 0.4606 ms | 0.000461 s
CRDTListHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 25800.87012987013 us | 25.8009 ms | 0.025801 s
CRDTMapHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 25666.4625 us | 25.6665 ms | 0.025666 s
Resolve nested tree with 50 leaves (cold caches)(RunTime): 1873.7421289355323 us | 1.8737 ms | 0.001874 s
Resolve nested tree with 200 leaves (cold caches)(RunTime): 8208.124 us | 8.2081 ms | 0.008208 s
Resolve nested tree with 800 leaves (cold caches)(RunTime): 38776.8431372549 us | 38.7768 ms | 0.038777 s
Import + resolve nested tree with 50 leaves (fresh peer)(RunTime): 5350.136 us | 5.3501 ms | 0.005350 s
Import + resolve nested tree with 200 leaves (fresh peer)(RunTime): 23838.876404494382 us | 23.8389 ms | 0.023839 s
Import + resolve nested tree with 800 leaves (fresh peer)(RunTime): 108900.46428571429 us | 108.9005 ms | 0.108900 s
OpIdKey view x100k(RunTime): 4783.278651685393 us | 4.7833 ms | 0.004783 s
OpIdKey hashCode x100k (cold)(RunTime): 19851.04 us | 19.8510 ms | 0.019851 s
OpIdKey map lookup x10k(RunTime): 534.45875 us | 0.5345 ms | 0.000534 s
OperationId map lookup x10k(RunTime): 353.48504047870466 us | 0.3535 ms | 0.000353 s
CRDTORSetHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 28706.567164179105 us | 28.7066 ms | 0.028707 s
PeerId generate x100(RunTime): 1633.9842578710645 us | 1.6340 ms | 0.001634 s
PeerId toUint8List x1000(RunTime): 319.26437699680514 us | 0.3193 ms | 0.000319 s
PeerId fromUint8List x1000(RunTime): 583.1665 us | 0.5832 ms | 0.000583 s
Import 1000 chained changes(RunTime): 9783.654166666667 us | 9.7837 ms | 0.009784 s
Import 10000 chained changes(RunTime): 123139.4375 us | 123.1394 ms | 0.123139 s
exportChangesNewerThan on 50000 changes / 10 peers (99% caught-up)(RunTime): 15.900196073872575 us | 0.0159 ms | 0.000016 s
takeSnapshot(pruneHistory) with 10000 changes(RunTime): 234092.1 us | 234.0921 ms | 0.234092 s
takeSnapshot(pruneHistory) with 100 concurrent heads(RunTime): 37842.6037735849 us | 37.8426 ms | 0.037843 s
Binary encode/decode 1000 changes(RunTime): 23586.69811320755 us | 23.5867 ms | 0.023587 s
Take snapshot with 1000 changes(RunTime): 1303.485 us | 1.3035 ms | 0.001303 s
CRDTTextHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 28516.326732673268 us | 28.5163 ms | 0.028516 s
CRDTTextHandler do 1000 operations and get value (incremental cache update: false)(RunTime): 35219.52 us | 35.2195 ms | 0.035220 s
Import 1000 concurrent changes(RunTime): 12419.775280898877 us | 12.4198 ms | 0.012420 s
VersionVector toBytes 10 peers x1000(RunTime): 4376.254 us | 4.3763 ms | 0.004376 s
VersionVector fromBytes 10 peers x1000(RunTime): 13826.442953020134 us | 13.8264 ms | 0.013826 s
VersionVector intersection 10 peers x1000(RunTime): 1900.1049475262369 us | 1.9001 ms | 0.001900 s
