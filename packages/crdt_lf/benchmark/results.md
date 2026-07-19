Apply 1000 changes(RunTime): 9546.07627118644 us | 9.5461 ms | 0.009546 s
Change toBytes x1000(RunTime): 595.44125 us | 0.5954 ms | 0.000595 s
Change fromBytes x1000(RunTime): 189.1826886250479 us | 0.1892 ms | 0.000189 s
Change roundtrip x1000(RunTime): 792.9955 us | 0.7930 ms | 0.000793 s
DAG addNode chain of 1000(RunTime): 1832.2098950524737 us | 1.8322 ms | 0.001832 s
DAG getAncestors chain of 200(RunTime): 74.72202900695575 us | 0.0747 ms | 0.000075 s
CRDTFugueListHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 33438.55737704918 us | 33.4386 ms | 0.033439 s
HLC toUint8List x100k(RunTime): 242.37557460554106 us | 0.2424 ms | 0.000242 s
HLC fromUint8List x100k(RunTime): 5034.1025 us | 5.0341 ms | 0.005034 s
HLC compareTo x100k(RunTime): 450.62056902985074 us | 0.4506 ms | 0.000451 s
CRDTListHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 26189.822784810127 us | 26.1898 ms | 0.026190 s
CRDTMapHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 25555.2987012987 us | 25.5553 ms | 0.025555 s
Resolve nested tree with 50 leaves (cold caches)(RunTime): 1901.3973013493253 us | 1.9014 ms | 0.001901 s
Resolve nested tree with 200 leaves (cold caches)(RunTime): 8824.116 us | 8.8241 ms | 0.008824 s
Resolve nested tree with 800 leaves (cold caches)(RunTime): 40378.72 us | 40.3787 ms | 0.040379 s
Import + resolve nested tree with 50 leaves (fresh peer)(RunTime): 5637.989130434783 us | 5.6380 ms | 0.005638 s
Import + resolve nested tree with 200 leaves (fresh peer)(RunTime): 26385.042372881355 us | 26.3850 ms | 0.026385 s
Import + resolve nested tree with 800 leaves (fresh peer)(RunTime): 125835.0 us | 125.8350 ms | 0.125835 s
OpIdKey view x100k(RunTime): 4847.137078651685 us | 4.8471 ms | 0.004847 s
OpIdKey hashCode x100k (cold)(RunTime): 20067.01 us | 20.0670 ms | 0.020067 s
OpIdKey map lookup x10k(RunTime): 536.82925 us | 0.5368 ms | 0.000537 s
OperationId map lookup x10k(RunTime): 364.0319343065693 us | 0.3640 ms | 0.000364 s
CRDTORSetHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 28368.954545454544 us | 28.3690 ms | 0.028369 s
PeerId generate x100(RunTime): 1618.127436281859 us | 1.6181 ms | 0.001618 s
PeerId toUint8List x1000(RunTime): 317.9982622432859 us | 0.3180 ms | 0.000318 s
PeerId fromUint8List x1000(RunTime): 590.91575 us | 0.5909 ms | 0.000591 s
Import 1000 chained changes(RunTime): 9518.153846153846 us | 9.5182 ms | 0.009518 s
Import 10000 chained changes(RunTime): 130580.21428571429 us | 130.5802 ms | 0.130580 s
exportChangesNewerThan on 50000 changes / 10 peers (99% caught-up)(RunTime): 15.636782838498679 us | 0.0156 ms | 0.000016 s
takeSnapshot(pruneHistory) with 10000 changes(RunTime): 240427.2 us | 240.4272 ms | 0.240427 s
takeSnapshot(pruneHistory) with 100 concurrent heads(RunTime): 38054.301886792455 us | 38.0543 ms | 0.038054 s
Binary encode/decode 1000 changes(RunTime): 24631.83870967742 us | 24.6318 ms | 0.024632 s
Take snapshot with 1000 changes(RunTime): 1286.1445 us | 1.2861 ms | 0.001286 s
CRDTTextHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 26857.051020408162 us | 26.8571 ms | 0.026857 s
CRDTTextHandler do 1000 operations and get value (incremental cache update: false)(RunTime): 29837.75903614458 us | 29.8378 ms | 0.029838 s
Import 1000 concurrent changes(RunTime): 9535.942408376963 us | 9.5359 ms | 0.009536 s
VersionVector toBytes 10 peers x1000(RunTime): 4320.772 us | 4.3208 ms | 0.004321 s
VersionVector fromBytes 10 peers x1000(RunTime): 13995.859060402685 us | 13.9959 ms | 0.013996 s
VersionVector intersection 10 peers x1000(RunTime): 1799.2698650674663 us | 1.7993 ms | 0.001799 s
