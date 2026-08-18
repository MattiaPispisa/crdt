Apply 1000 changes(RunTime): 972.0187250996016 us | 0.9720 ms | 0.000972 s
Change toBytes x1000(RunTime): 59.898 us | 0.0599 ms | 0.000060 s
Change fromBytes x1000(RunTime): 19.00118106486332 us | 0.0190 ms | 0.000019 s
Change roundtrip x1000(RunTime): 79.556975 us | 0.0796 ms | 0.000080 s
DAG addNode chain of 1000(RunTime): 184.0147676161919 us | 0.1840 ms | 0.000184 s
DAG getAncestors chain of 200(RunTime): 7.54764781881745 us | 0.0075 ms | 0.000008 s
CRDTFugueListHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 3187.955223880597 us | 3.1880 ms | 0.003188 s
Fugue text takeSnapshot of 10000 elements (tombstones: false)(RunTime): 1160.7540229885058 us | 1.1608 ms | 0.001161 s
Fugue text restore of 10000 elements from snapshot (tombstones: false)(RunTime): 4223.3557692307695 us | 4.2234 ms | 0.004223 s
Fugue text takeSnapshot of 10000 elements (tombstones: true)(RunTime): 1256.7826347305388 us | 1.2568 ms | 0.001257 s
Fugue text restore of 10000 elements from snapshot (tombstones: true)(RunTime): 4965.147887323944 us | 4.9651 ms | 0.004965 s
Fugue text takeSnapshot of 100000 elements (tombstones: false)(RunTime): 30515.1625 us | 30.5152 ms | 0.030515 s
Fugue text restore of 100000 elements from snapshot (tombstones: false)(RunTime): 69264.16 us | 69.2642 ms | 0.069264 s
Fugue text takeSnapshot of 100000 elements (tombstones: true)(RunTime): 63115.0125 us | 63.1150 ms | 0.063115 s
Fugue text restore of 100000 elements from snapshot (tombstones: true)(RunTime): 59074.340000000004 us | 59.0743 ms | 0.059074 s
Fugue text keystroke + length on 30000 chars(RunTime): 2.98 us | 0.0030 ms | 0.000003 s
Fugue text keystroke + value on 30000 chars(RunTime): 626.46 us | 0.6265 ms | 0.000626 s
Fugue text update on 30000 chars(RunTime): 2.12 us | 0.0021 ms | 0.000002 s
FugueTree append 50000 elements(RunTime): 30223.414285714283 us | 30.2234 ms | 0.030223 s
FugueTree prepend 50000 elements(RunTime): 73001.6 us | 73.0016 ms | 0.073002 s
FugueTree random insert 50000 elements(RunTime): 78412.16666666666 us | 78.4122 ms | 0.078412 s
FugueTree values() over 50000 live elements(RunTime): 836.1697160883281 us | 0.8362 ms | 0.000836 s
FugueTree values() over 50000 elements, 90% tombstones(RunTime): 127.29384999999999 us | 0.1273 ms | 0.000127 s
HLC toUint8List x100k(RunTime): 25.494108507056843 us | 0.0255 ms | 0.000025 s
HLC fromUint8List x100k(RunTime): 504.23024999999996 us | 0.5042 ms | 0.000504 s
HLC compareTo x100k(RunTime): 45.10257847533632 us | 0.0451 ms | 0.000045 s
CRDTListHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 2594.1753246753246 us | 2.5942 ms | 0.002594 s
CRDTMapHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 2607.2013157894735 us | 2.6072 ms | 0.002607 s
Resolve nested tree with 50 leaves (cold caches)(RunTime): 194.44542728635682 us | 0.1944 ms | 0.000194 s
Resolve nested tree with 200 leaves (cold caches)(RunTime): 839.5360000000001 us | 0.8395 ms | 0.000840 s
Resolve nested tree with 800 leaves (cold caches)(RunTime): 3527.074137931035 us | 3.5271 ms | 0.003527 s
Import + resolve nested tree with 50 leaves (fresh peer)(RunTime): 547.458988764045 us | 0.5475 ms | 0.000547 s
Import + resolve nested tree with 200 leaves (fresh peer)(RunTime): 2307.3622641509437 us | 2.3074 ms | 0.002307 s
Import + resolve nested tree with 800 leaves (fresh peer)(RunTime): 8691.903571428571 us | 8.6919 ms | 0.008692 s
OpIdKey view x100k(RunTime): 475.6741573033708 us | 0.4757 ms | 0.000476 s
OpIdKey hashCode x100k (cold)(RunTime): 1997.7549999999999 us | 1.9978 ms | 0.001998 s
OpIdKey map lookup x10k(RunTime): 54.363775 us | 0.0544 ms | 0.000054 s
OperationId map lookup x10k(RunTime): 35.83719392314567 us | 0.0358 ms | 0.000036 s
CRDTORSetHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 2898.239130434783 us | 2.8982 ms | 0.002898 s
PeerId generate x100(RunTime): 162.1632683658171 us | 0.1622 ms | 0.000162 s
PeerId toUint8List x1000(RunTime): 32.54894064370047 us | 0.0325 ms | 0.000033 s
PeerId fromUint8List x1000(RunTime): 58.30685 us | 0.0583 ms | 0.000058 s
Fugue text remote keystroke + read on 2000 chars(RunTime): 66.16 us | 0.0662 ms | 0.000066 s
Fugue text remote keystroke + read on 10000 chars(RunTime): 187.11 us | 0.1871 ms | 0.000187 s
Fugue text remote keystroke + read on 30000 chars(RunTime): 703.555 us | 0.7036 ms | 0.000704 s
Text remote keystroke + read on 2000 chars(RunTime): 9.185 us | 0.0092 ms | 0.000009 s
Text remote keystroke + read on 10000 chars(RunTime): 12.995 us | 0.0130 ms | 0.000013 s
Text remote keystroke + read on 30000 chars(RunTime): 21.12 us | 0.0211 ms | 0.000021 s
Map remote set + read on 1000 keys(RunTime): 9.4 us | 0.0094 ms | 0.000009 s
Map remote set + read on 5000 keys(RunTime): 5.07 us | 0.0051 ms | 0.000005 s
OR-set remote add from the past + read on 1000 values(RunTime): 34.09 us | 0.0341 ms | 0.000034 s
OR-set remote add from the past + read on 5000 values(RunTime): 104.55 us | 0.1046 ms | 0.000105 s
OR-map remote put from the past + read on 1000 keys(RunTime): 88.885 us | 0.0889 ms | 0.000089 s
OR-map remote put from the past + read on 5000 keys(RunTime): 248.445 us | 0.2484 ms | 0.000248 s
Movable list remote move from the past + read on 1000 items(RunTime): 46.51 us | 0.0465 ms | 0.000047 s
Movable list remote move from the past + read on 5000 items(RunTime): 163.28 us | 0.1633 ms | 0.000163 s
Import 1000 chained changes(RunTime): 963.1513944223109 us | 0.9632 ms | 0.000963 s
Import 10000 chained changes(RunTime): 11337.394736842105 us | 11.3374 ms | 0.011337 s
exportChangesNewerThan on 50000 changes / 10 peers (99% caught-up)(RunTime): 1.5363568182159089 us | 0.0015 ms | 0.000002 s
takeSnapshot(pruneHistory) with 10000 changes(RunTime): 24235.71818181818 us | 24.2357 ms | 0.024236 s
takeSnapshot(pruneHistory) with 100 concurrent heads(RunTime): 3966.7784313725488 us | 3.9668 ms | 0.003967 s
Binary encode/decode 1000 changes(RunTime): 2003.4417582417584 us | 2.0034 ms | 0.002003 s
Take snapshot with 1000 changes(RunTime): 128.9462 us | 0.1289 ms | 0.000129 s
CRDTTextHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 2986.523188405797 us | 2.9865 ms | 0.002987 s
CRDTTextHandler do 1000 operations and get value (incremental cache update: false)(RunTime): 2961.0347826086954 us | 2.9610 ms | 0.002961 s
Import 1000 concurrent changes(RunTime): 1021.2004000000001 us | 1.0212 ms | 0.001021 s
VersionVector toBytes 10 peers x1000(RunTime): 438.6086 us | 0.4386 ms | 0.000439 s
VersionVector fromBytes 10 peers x1000(RunTime): 1464.0528985507246 us | 1.4641 ms | 0.001464 s
VersionVector intersection 10 peers x1000(RunTime): 189.7221139430285 us | 0.1897 ms | 0.000190 s
