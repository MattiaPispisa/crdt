Apply 1000 changes(RunTime): 980.4183266932271 us | 0.9804 ms | 0.000980 s
Change toBytes x1000(RunTime): 60.1345 us | 0.0601 ms | 0.000060 s
Change fromBytes x1000(RunTime): 19.007267358796078 us | 0.0190 ms | 0.000019 s
Change roundtrip x1000(RunTime): 79.17775 us | 0.0792 ms | 0.000079 s
Change size, fugue text update(Size): 96 bytes total | 45 bytes payload | stamped: true
Change size, or-set add(Size): 59 bytes total | 32 bytes payload | stamped: true
Change size, or-map put(Size): 66 bytes total | 39 bytes payload | stamped: true
Change size, movable list move(Size): 145 bytes total | 94 bytes payload | stamped: true
DAG addNode chain of 1000(RunTime): 186.5575712143928 us | 0.1866 ms | 0.000187 s
DAG getAncestors chain of 200(RunTime): 7.445084708389989 us | 0.0074 ms | 0.000007 s
CRDTFugueListHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 3026.2084507042255 us | 3.0262 ms | 0.003026 s
Fugue text snapshot of 10000 elements (tombstones: false)(Size): 10044 bytes handler blob | 10144 bytes total
Fugue text takeSnapshot of 10000 elements (tombstones: false)(RunTime): 1090.7492146596858 us | 1.0907 ms | 0.001091 s
Fugue text restore of 10000 elements from snapshot (tombstones: false)(RunTime): 4244.208196721312 us | 4.2442 ms | 0.004244 s
Fugue text snapshot of 10000 elements (tombstones: true)(Size): 109959 bytes handler blob | 110060 bytes total
Fugue text takeSnapshot of 10000 elements (tombstones: true)(RunTime): 3218.28961038961 us | 3.2183 ms | 0.003218 s
Fugue text restore of 10000 elements from snapshot (tombstones: true)(RunTime): 3758.6013333333335 us | 3.7586 ms | 0.003759 s
Fugue text snapshot of 100000 elements (tombstones: false)(Size): 100047 bytes handler blob | 100148 bytes total
Fugue text takeSnapshot of 100000 elements (tombstones: false)(RunTime): 35758.98888888889 us | 35.7590 ms | 0.035759 s
Fugue text restore of 100000 elements from snapshot (tombstones: false)(RunTime): 98413.55 us | 98.4136 ms | 0.098414 s
Fugue text snapshot of 100000 elements (tombstones: true)(Size): 1141769 bytes handler blob | 1141870 bytes total
Fugue text takeSnapshot of 100000 elements (tombstones: true)(RunTime): 61101.13333333334 us | 61.1011 ms | 0.061101 s
Fugue text restore of 100000 elements from snapshot (tombstones: true)(RunTime): 51434.08 us | 51.4341 ms | 0.051434 s
Movable list snapshot of 10000 elements(Size): 922400 bytes handler blob | 922504 bytes total | 92.2 bytes per element
Fugue text keystroke + length on 30000 chars(RunTime): 3.07 us | 0.0031 ms | 0.000003 s
Fugue text keystroke + value on 30000 chars(RunTime): 620.57 us | 0.6206 ms | 0.000621 s
Fugue text update on 30000 chars(RunTime): 2.135 us | 0.0021 ms | 0.000002 s
FugueTree append 50000 elements(RunTime): 30132.585714285717 us | 30.1326 ms | 0.030133 s
FugueTree prepend 50000 elements(RunTime): 74244.26666666666 us | 74.2443 ms | 0.074244 s
FugueTree random insert 50000 elements(RunTime): 77109.56666666667 us | 77.1096 ms | 0.077110 s
FugueTree values() over 50000 live elements(RunTime): 847.8936440677966 us | 0.8479 ms | 0.000848 s
FugueTree values() over 50000 elements, 90% tombstones(RunTime): 132.39884999999998 us | 0.1324 ms | 0.000132 s
Fugue text retained RSS for 10000 elements(Size): 9912320 bytes (before: 209911808, after: 219824128)
Fugue text retained RSS for 100000 elements(Size): 91914240 bytes (before: 219824128, after: 311738368)
HLC toUint8List x100k(RunTime): 24.919121976193523 us | 0.0249 ms | 0.000025 s
HLC fromUint8List x100k(RunTime): 508.47025 us | 0.5085 ms | 0.000508 s
HLC compareTo x100k(RunTime): 45.65748314606741 us | 0.0457 ms | 0.000046 s
CRDTListHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 2614.2052631578945 us | 2.6142 ms | 0.002614 s
CRDTMapHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 2637.7417721518987 us | 2.6377 ms | 0.002638 s
Resolve nested tree with 50 leaves (cold caches)(RunTime): 193.4337331334333 us | 0.1934 ms | 0.000193 s
Resolve nested tree with 200 leaves (cold caches)(RunTime): 829.4936 us | 0.8295 ms | 0.000829 s
Resolve nested tree with 800 leaves (cold caches)(RunTime): 3482.693220338983 us | 3.4827 ms | 0.003483 s
Import + resolve nested tree with 50 leaves (fresh peer)(RunTime): 530.1458426966292 us | 0.5301 ms | 0.000530 s
Import + resolve nested tree with 200 leaves (fresh peer)(RunTime): 2114.186440677966 us | 2.1142 ms | 0.002114 s
Import + resolve nested tree with 800 leaves (fresh peer)(RunTime): 11309.685185185186 us | 11.3097 ms | 0.011310 s
OpIdKey view x100k(RunTime): 475.7092134831461 us | 0.4757 ms | 0.000476 s
OpIdKey hashCode x100k (cold)(RunTime): 1986.574 us | 1.9866 ms | 0.001987 s
OpIdKey map lookup x10k(RunTime): 53.787 us | 0.0538 ms | 0.000054 s
OperationId map lookup x10k(RunTime): 35.8806237677003 us | 0.0359 ms | 0.000036 s
CRDTORSetHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 2898.301408450704 us | 2.8983 ms | 0.002898 s
PeerId generate x100(RunTime): 163.11836581709144 us | 0.1631 ms | 0.000163 s
PeerId toUint8List x1000(RunTime): 31.8708253968254 us | 0.0319 ms | 0.000032 s
PeerId fromUint8List x1000(RunTime): 58.064675 us | 0.0581 ms | 0.000058 s
Fugue text remote keystroke + read on 2000 chars(RunTime): 57.315 us | 0.0573 ms | 0.000057 s
Fugue text remote keystroke + read on 10000 chars(RunTime): 171.84 us | 0.1718 ms | 0.000172 s
Fugue text remote keystroke + read on 30000 chars(RunTime): 670.355 us | 0.6704 ms | 0.000670 s
Text remote keystroke + read on 2000 chars(RunTime): 9.37 us | 0.0094 ms | 0.000009 s
Text remote keystroke + read on 10000 chars(RunTime): 12.795 us | 0.0128 ms | 0.000013 s
Text remote keystroke + read on 30000 chars(RunTime): 21.005 us | 0.0210 ms | 0.000021 s
Map remote set + read on 1000 keys(RunTime): 8.72 us | 0.0087 ms | 0.000009 s
Map remote set + read on 5000 keys(RunTime): 12.79 us | 0.0128 ms | 0.000013 s
OR-set remote add from the past + read on 1000 values(RunTime): 33.17 us | 0.0332 ms | 0.000033 s
OR-set remote add from the past + read on 5000 values(RunTime): 100.105 us | 0.1001 ms | 0.000100 s
OR-map remote put from the past + read on 1000 keys(RunTime): 84.39 us | 0.0844 ms | 0.000084 s
OR-map remote put from the past + read on 5000 keys(RunTime): 255.885 us | 0.2559 ms | 0.000256 s
Movable list remote move from the past + read on 1000 items(RunTime): 41.955 us | 0.0420 ms | 0.000042 s
Movable list remote move from the past + read on 5000 items(RunTime): 155.13 us | 0.1551 ms | 0.000155 s
Import 1000 chained changes(RunTime): 961.3263999999999 us | 0.9613 ms | 0.000961 s
Import 10000 chained changes(RunTime): 11334.985714285714 us | 11.3350 ms | 0.011335 s
exportChangesNewerThan on 50000 changes / 10 peers (99% caught-up)(RunTime): 2.8017737322626775 us | 0.0028 ms | 0.000003 s
takeSnapshot(pruneHistory) with 10000 changes(RunTime): 24500.02 us | 24.5000 ms | 0.024500 s
takeSnapshot(pruneHistory) with 100 concurrent heads(RunTime): 3928.9461538461537 us | 3.9289 ms | 0.003929 s
Binary encode/decode 1000 changes(RunTime): 2469.1149532710283 us | 2.4691 ms | 0.002469 s
Take snapshot with 1000 changes(RunTime): 131.63065 us | 0.1316 ms | 0.000132 s
CRDTTextHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 3033.666153846154 us | 3.0337 ms | 0.003034 s
CRDTTextHandler do 1000 operations and get value (incremental cache update: false)(RunTime): 2850.801219512195 us | 2.8508 ms | 0.002851 s
Import 1000 concurrent changes(RunTime): 1007.2533333333333 us | 1.0073 ms | 0.001007 s
VersionVector toBytes 10 peers x1000(RunTime): 449.3344 us | 0.4493 ms | 0.000449 s
VersionVector fromBytes 10 peers x1000(RunTime): 1428.860839160839 us | 1.4289 ms | 0.001429 s
VersionVector intersection 10 peers x1000(RunTime): 184.09677661169414 us | 0.1841 ms | 0.000184 s
