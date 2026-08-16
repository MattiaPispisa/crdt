Apply 1000 changes(RunTime): 9372.952606635072 us | 9.3730 ms | 0.009373 s
Change toBytes x1000(RunTime): 591.29725 us | 0.5913 ms | 0.000591 s
Change fromBytes x1000(RunTime): 193.67722534081796 us | 0.1937 ms | 0.000194 s
Change roundtrip x1000(RunTime): 787.19025 us | 0.7872 ms | 0.000787 s
DAG addNode chain of 1000(RunTime): 1828.4775112443779 us | 1.8285 ms | 0.001828 s
DAG getAncestors chain of 200(RunTime): 74.31465856676792 us | 0.0743 ms | 0.000074 s
CRDTFugueListHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 31394.268656716416 us | 31.3943 ms | 0.031394 s
Fugue text snapshot of 10000 elements (tombstones: false)(Size): 10044 bytes handler blob | 10144 bytes total
Fugue text takeSnapshot of 10000 elements (tombstones: false)(RunTime): 10982.638743455498 us | 10.9826 ms | 0.010983 s
Fugue text restore of 10000 elements from snapshot (tombstones: false)(RunTime): 42833.816666666666 us | 42.8338 ms | 0.042834 s
Fugue text snapshot of 10000 elements (tombstones: true)(Size): 109959 bytes handler blob | 110060 bytes total
Fugue text takeSnapshot of 10000 elements (tombstones: true)(RunTime): 32471.632911392404 us | 32.4716 ms | 0.032472 s
Fugue text restore of 10000 elements from snapshot (tombstones: true)(RunTime): 37572.72727272727 us | 37.5727 ms | 0.037573 s
Fugue text keystroke + length on 30000 chars(RunTime): 80.09464393434295 us | 0.0801 ms | 0.000080 s
Fugue text keystroke + value on 30000 chars(RunTime): 7664.699300699301 us | 7.6647 ms | 0.007665 s
FugueTree append 50000 elements(RunTime): 301598.85714285716 us | 301.5989 ms | 0.301599 s
FugueTree prepend 50000 elements(RunTime): 739105.3333333334 us | 739.1053 ms | 0.739105 s
FugueTree random insert 50000 elements(RunTime): 770191.3333333334 us | 770.1913 ms | 0.770191 s
FugueTree values() over 50000 live elements(RunTime): 8479.296610169491 us | 8.4793 ms | 0.008479 s
FugueTree values() over 50000 elements, 90% tombstones(RunTime): 1375.9305 us | 1.3759 ms | 0.001376 s
HLC toUint8List x100k(RunTime): 245.5240881364372 us | 0.2455 ms | 0.000246 s
HLC fromUint8List x100k(RunTime): 5066.2025 us | 5.0662 ms | 0.005066 s
HLC compareTo x100k(RunTime): 460.9072951739618 us | 0.4609 ms | 0.000461 s
CRDTListHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 24981.521276595744 us | 24.9815 ms | 0.024982 s
CRDTMapHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 26240.855263157893 us | 26.2409 ms | 0.026241 s
Resolve nested tree with 50 leaves (cold caches)(RunTime): 1944.4130434782608 us | 1.9444 ms | 0.001944 s
Resolve nested tree with 200 leaves (cold caches)(RunTime): 8450.36 us | 8.4504 ms | 0.008450 s
Resolve nested tree with 800 leaves (cold caches)(RunTime): 34832.206896551725 us | 34.8322 ms | 0.034832 s
Import + resolve nested tree with 50 leaves (fresh peer)(RunTime): 5453.2575 us | 5.4533 ms | 0.005453 s
Import + resolve nested tree with 200 leaves (fresh peer)(RunTime): 21911.8 us | 21.9118 ms | 0.021912 s
Import + resolve nested tree with 800 leaves (fresh peer)(RunTime): 148034.61904761905 us | 148.0346 ms | 0.148035 s
OpIdKey view x100k(RunTime): 4775.074157303371 us | 4.7751 ms | 0.004775 s
OpIdKey hashCode x100k (cold)(RunTime): 20194.96 us | 20.1950 ms | 0.020195 s
OpIdKey map lookup x10k(RunTime): 539.469 us | 0.5395 ms | 0.000539 s
OperationId map lookup x10k(RunTime): 351.7657293497364 us | 0.3518 ms | 0.000352 s
CRDTORSetHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 29314.93650793651 us | 29.3149 ms | 0.029315 s
PeerId generate x100(RunTime): 1621.690404797601 us | 1.6217 ms | 0.001622 s
PeerId toUint8List x1000(RunTime): 317.27145110410095 us | 0.3173 ms | 0.000317 s
PeerId fromUint8List x1000(RunTime): 587.331 us | 0.5873 ms | 0.000587 s
Fugue text remote keystroke + read on 2000 chars(RunTime): 75.775 us | 0.0758 ms | 0.000076 s
Fugue text remote keystroke + read on 10000 chars(RunTime): 229.13 us | 0.2291 ms | 0.000229 s
Fugue text remote keystroke + read on 30000 chars(RunTime): 736.59 us | 0.7366 ms | 0.000737 s
Text remote keystroke + read on 2000 chars(RunTime): 9.26 us | 0.0093 ms | 0.000009 s
Text remote keystroke + read on 10000 chars(RunTime): 13.38 us | 0.0134 ms | 0.000013 s
Text remote keystroke + read on 30000 chars(RunTime): 22.685 us | 0.0227 ms | 0.000023 s
Map remote set + read on 1000 keys(RunTime): 9.64 us | 0.0096 ms | 0.000010 s
Map remote set + read on 5000 keys(RunTime): 4.76 us | 0.0048 ms | 0.000005 s
OR-set remote add from the past + read on 1000 values(RunTime): 30.125 us | 0.0301 ms | 0.000030 s
OR-set remote add from the past + read on 5000 values(RunTime): 106.37 us | 0.1064 ms | 0.000106 s
OR-map remote put from the past + read on 1000 keys(RunTime): 70.06 us | 0.0701 ms | 0.000070 s
OR-map remote put from the past + read on 5000 keys(RunTime): 250.21 us | 0.2502 ms | 0.000250 s
Import 1000 chained changes(RunTime): 9579.72908366534 us | 9.5797 ms | 0.009580 s
Import 10000 chained changes(RunTime): 116547.27272727272 us | 116.5473 ms | 0.116547 s
exportChangesNewerThan on 50000 changes / 10 peers (99% caught-up)(RunTime): 15.85741631985616 us | 0.0159 ms | 0.000016 s
takeSnapshot(pruneHistory) with 10000 changes(RunTime): 251114.6 us | 251.1146 ms | 0.251115 s
takeSnapshot(pruneHistory) with 100 concurrent heads(RunTime): 38188.28846153846 us | 38.1883 ms | 0.038188 s
Binary encode/decode 1000 changes(RunTime): 24113.708860759492 us | 24.1137 ms | 0.024114 s
Take snapshot with 1000 changes(RunTime): 1298.8695 us | 1.2989 ms | 0.001299 s
CRDTTextHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 29678.154761904763 us | 29.6782 ms | 0.029678 s
CRDTTextHandler do 1000 operations and get value (incremental cache update: false)(RunTime): 29577.14285714286 us | 29.5771 ms | 0.029577 s
Import 1000 concurrent changes(RunTime): 9786.333333333334 us | 9.7863 ms | 0.009786 s
VersionVector toBytes 10 peers x1000(RunTime): 4403.164 us | 4.4032 ms | 0.004403 s
VersionVector fromBytes 10 peers x1000(RunTime): 14302.13986013986 us | 14.3021 ms | 0.014302 s
VersionVector intersection 10 peers x1000(RunTime): 1850.3215892053972 us | 1.8503 ms | 0.001850 s
