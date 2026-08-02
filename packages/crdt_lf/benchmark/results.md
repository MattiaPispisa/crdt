Apply 1000 changes(RunTime): 9347.009478672986 us | 9.3470 ms | 0.009347 s
Change toBytes x1000(RunTime): 594.9905 us | 0.5950 ms | 0.000595 s
Change fromBytes x1000(RunTime): 191.69114163903365 us | 0.1917 ms | 0.000192 s
Change roundtrip x1000(RunTime): 785.94375 us | 0.7859 ms | 0.000786 s
DAG addNode chain of 1000(RunTime): 1824.708395802099 us | 1.8247 ms | 0.001825 s
DAG getAncestors chain of 200(RunTime): 73.89092646356254 us | 0.0739 ms | 0.000074 s
CRDTFugueListHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 32231.257575757576 us | 32.2313 ms | 0.032231 s
FugueTree append 50000 elements(RunTime): 297636.85714285716 us | 297.6369 ms | 0.297637 s
FugueTree prepend 50000 elements(RunTime): 737614.0 us | 737.6140 ms | 0.737614 s
FugueTree random insert 50000 elements(RunTime): 751214.6666666666 us | 751.2147 ms | 0.751215 s
FugueTree values() over 50000 live elements(RunTime): 8307.044 us | 8.3070 ms | 0.008307 s
FugueTree values() over 50000 elements, 90% tombstones(RunTime): 1309.318 us | 1.3093 ms | 0.001309 s
HLC toUint8List x100k(RunTime): 240.90384853359734 us | 0.2409 ms | 0.000241 s
HLC fromUint8List x100k(RunTime): 4990.537078651685 us | 4.9905 ms | 0.004991 s
HLC compareTo x100k(RunTime): 449.84409799554567 us | 0.4498 ms | 0.000450 s
CRDTListHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 25870.973684210527 us | 25.8710 ms | 0.025871 s
CRDTMapHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 26113.68831168831 us | 26.1137 ms | 0.026114 s
Resolve nested tree with 50 leaves (cold caches)(RunTime): 1884.535232383808 us | 1.8845 ms | 0.001885 s
Resolve nested tree with 200 leaves (cold caches)(RunTime): 8147.12 us | 8.1471 ms | 0.008147 s
Resolve nested tree with 800 leaves (cold caches)(RunTime): 33889.91525423729 us | 33.8899 ms | 0.033890 s
Import + resolve nested tree with 50 leaves (fresh peer)(RunTime): 5537.27875 us | 5.5373 ms | 0.005537 s
Import + resolve nested tree with 200 leaves (fresh peer)(RunTime): 22936.9375 us | 22.9369 ms | 0.022937 s
Import + resolve nested tree with 800 leaves (fresh peer)(RunTime): 114342.23529411765 us | 114.3422 ms | 0.114342 s
OpIdKey view x100k(RunTime): 4768.564044943821 us | 4.7686 ms | 0.004769 s
OpIdKey hashCode x100k (cold)(RunTime): 19742.873786407767 us | 19.7429 ms | 0.019743 s
OpIdKey map lookup x10k(RunTime): 541.40875 us | 0.5414 ms | 0.000541 s
OperationId map lookup x10k(RunTime): 353.25718849840257 us | 0.3533 ms | 0.000353 s
CRDTORSetHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 29181.3661971831 us | 29.1814 ms | 0.029181 s
PeerId generate x100(RunTime): 1609.156671664168 us | 1.6092 ms | 0.001609 s
PeerId toUint8List x1000(RunTime): 317.0402225755167 us | 0.3170 ms | 0.000317 s
PeerId fromUint8List x1000(RunTime): 582.61675 us | 0.5826 ms | 0.000583 s
Fugue text remote keystroke + read on 2000 chars(RunTime): 62.425 us | 0.0624 ms | 0.000062 s
Fugue text remote keystroke + read on 10000 chars(RunTime): 199.9 us | 0.1999 ms | 0.000200 s
Fugue text remote keystroke + read on 30000 chars(RunTime): 685.49 us | 0.6855 ms | 0.000685 s
Text remote keystroke + read on 2000 chars(RunTime): 8.71 us | 0.0087 ms | 0.000009 s
Text remote keystroke + read on 10000 chars(RunTime): 9.085 us | 0.0091 ms | 0.000009 s
Text remote keystroke + read on 30000 chars(RunTime): 13.215 us | 0.0132 ms | 0.000013 s
Map remote set + read on 1000 keys(RunTime): 10.965 us | 0.0110 ms | 0.000011 s
Map remote set + read on 5000 keys(RunTime): 5.41 us | 0.0054 ms | 0.000005 s
OR-set remote add from the past + read on 1000 values(RunTime): 29.235 us | 0.0292 ms | 0.000029 s
OR-set remote add from the past + read on 5000 values(RunTime): 113.385 us | 0.1134 ms | 0.000113 s
OR-map remote put from the past + read on 1000 keys(RunTime): 68.485 us | 0.0685 ms | 0.000068 s
OR-map remote put from the past + read on 5000 keys(RunTime): 251.46 us | 0.2515 ms | 0.000251 s
Import 1000 chained changes(RunTime): 9483.505747126437 us | 9.4835 ms | 0.009484 s
Import 10000 chained changes(RunTime): 123518.77272727272 us | 123.5188 ms | 0.123519 s
exportChangesNewerThan on 50000 changes / 10 peers (99% caught-up)(RunTime): 15.562057768167833 us | 0.0156 ms | 0.000016 s
takeSnapshot(pruneHistory) with 10000 changes(RunTime): 257068.6 us | 257.0686 ms | 0.257069 s
takeSnapshot(pruneHistory) with 100 concurrent heads(RunTime): 37669.61111111111 us | 37.6696 ms | 0.037670 s
Binary encode/decode 1000 changes(RunTime): 24513.68316831683 us | 24.5137 ms | 0.024514 s
Take snapshot with 1000 changes(RunTime): 1291.433 us | 1.2914 ms | 0.001291 s
CRDTTextHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 27469.95348837209 us | 27.4700 ms | 0.027470 s
CRDTTextHandler do 1000 operations and get value (incremental cache update: false)(RunTime): 28575.761904761905 us | 28.5758 ms | 0.028576 s
Import 1000 concurrent changes(RunTime): 9537.445692883895 us | 9.5374 ms | 0.009537 s
VersionVector toBytes 10 peers x1000(RunTime): 4476.036 us | 4.4760 ms | 0.004476 s
VersionVector fromBytes 10 peers x1000(RunTime): 14611.934782608696 us | 14.6119 ms | 0.014612 s
VersionVector intersection 10 peers x1000(RunTime): 1934.9400299850074 us | 1.9349 ms | 0.001935 s
