Apply 1000 changes(RunTime): 969.3693227091633 us | 0.9694 ms | 0.000969 s
Change toBytes x1000(RunTime): 59.27645 us | 0.0593 ms | 0.000059 s
Change fromBytes x1000(RunTime): 19.11188698856657 us | 0.0191 ms | 0.000019 s
Change roundtrip x1000(RunTime): 78.2587 us | 0.0783 ms | 0.000078 s
DAG addNode chain of 1000(RunTime): 186.2507496251874 us | 0.1863 ms | 0.000186 s
DAG getAncestors chain of 200(RunTime): 7.495998641047903 us | 0.0075 ms | 0.000007 s
CRDTFugueListHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 3112.2352941176473 us | 3.1122 ms | 0.003112 s
Fugue text takeSnapshot of 10000 elements (tombstones: false)(RunTime): 1186.7885057471265 us | 1.1868 ms | 0.001187 s
Fugue text restore of 10000 elements from snapshot (tombstones: false)(RunTime): 4206.231818181818 us | 4.2062 ms | 0.004206 s
Fugue text takeSnapshot of 10000 elements (tombstones: true)(RunTime): 1272.77 us | 1.2728 ms | 0.001273 s
Fugue text restore of 10000 elements from snapshot (tombstones: true)(RunTime): 5271.736 us | 5.2717 ms | 0.005272 s
Fugue text takeSnapshot of 100000 elements (tombstones: false)(RunTime): 32409.644444444442 us | 32.4096 ms | 0.032410 s
Fugue text restore of 100000 elements from snapshot (tombstones: false)(RunTime): 78834.0 us | 78.8340 ms | 0.078834 s
Fugue text takeSnapshot of 100000 elements (tombstones: true)(RunTime): 69336.225 us | 69.3362 ms | 0.069336 s
Fugue text restore of 100000 elements from snapshot (tombstones: true)(RunTime): 43017.86 us | 43.0179 ms | 0.043018 s
Fugue text keystroke + length on 30000 chars(RunTime): 2.94 us | 0.0029 ms | 0.000003 s
Fugue text keystroke + value on 30000 chars(RunTime): 616.465 us | 0.6165 ms | 0.000616 s
Fugue text update on 30000 chars(RunTime): 2.06 us | 0.0021 ms | 0.000002 s
FugueTree append 50000 elements(RunTime): 29989.557142857142 us | 29.9896 ms | 0.029990 s
FugueTree prepend 50000 elements(RunTime): 71675.5 us | 71.6755 ms | 0.071676 s
FugueTree random insert 50000 elements(RunTime): 77366.93333333333 us | 77.3669 ms | 0.077367 s
FugueTree values() over 50000 live elements(RunTime): 888.3811659192825 us | 0.8884 ms | 0.000888 s
FugueTree values() over 50000 elements, 90% tombstones(RunTime): 127.69745 us | 0.1277 ms | 0.000128 s
HLC toUint8List x100k(RunTime): 25.13807483935996 us | 0.0251 ms | 0.000025 s
HLC fromUint8List x100k(RunTime): 504.85749999999996 us | 0.5049 ms | 0.000505 s
HLC compareTo x100k(RunTime): 45.541165919282506 us | 0.0455 ms | 0.000046 s
CRDTListHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 2604.4434210526315 us | 2.6044 ms | 0.002604 s
CRDTMapHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 2597.0430379746836 us | 2.5970 ms | 0.002597 s
Resolve nested tree with 50 leaves (cold caches)(RunTime): 188.7409295352324 us | 0.1887 ms | 0.000189 s
Resolve nested tree with 200 leaves (cold caches)(RunTime): 821.332 us | 0.8213 ms | 0.000821 s
Resolve nested tree with 800 leaves (cold caches)(RunTime): 3402.4551724137928 us | 3.4025 ms | 0.003402 s
Import + resolve nested tree with 50 leaves (fresh peer)(RunTime): 524.2790155440414 us | 0.5243 ms | 0.000524 s
Import + resolve nested tree with 200 leaves (fresh peer)(RunTime): 2182.069892473118 us | 2.1821 ms | 0.002182 s
Import + resolve nested tree with 800 leaves (fresh peer)(RunTime): 8802.206896551725 us | 8.8022 ms | 0.008802 s
OpIdKey view x100k(RunTime): 475.6640449438202 us | 0.4757 ms | 0.000476 s
OpIdKey hashCode x100k (cold)(RunTime): 2003.051 us | 2.0031 ms | 0.002003 s
OpIdKey map lookup x10k(RunTime): 55.017250000000004 us | 0.0550 ms | 0.000055 s
OperationId map lookup x10k(RunTime): 35.77735779816514 us | 0.0358 ms | 0.000036 s
CRDTORSetHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 2901.5732394366196 us | 2.9016 ms | 0.002902 s
PeerId generate x100(RunTime): 163.35209895052475 us | 0.1634 ms | 0.000163 s
PeerId toUint8List x1000(RunTime): 32.524729095908135 us | 0.0325 ms | 0.000033 s
PeerId fromUint8List x1000(RunTime): 58.87495 us | 0.0589 ms | 0.000059 s
Fugue text remote keystroke + read on 2000 chars(RunTime): 64.625 us | 0.0646 ms | 0.000065 s
Fugue text remote keystroke + read on 10000 chars(RunTime): 187.15 us | 0.1872 ms | 0.000187 s
Fugue text remote keystroke + read on 30000 chars(RunTime): 684.09 us | 0.6841 ms | 0.000684 s
Text remote keystroke + read on 2000 chars(RunTime): 8.92 us | 0.0089 ms | 0.000009 s
Text remote keystroke + read on 10000 chars(RunTime): 11.59 us | 0.0116 ms | 0.000012 s
Text remote keystroke + read on 30000 chars(RunTime): 19.41 us | 0.0194 ms | 0.000019 s
Map remote set + read on 1000 keys(RunTime): 18.695 us | 0.0187 ms | 0.000019 s
Map remote set + read on 5000 keys(RunTime): 11.83 us | 0.0118 ms | 0.000012 s
OR-set remote add from the past + read on 1000 values(RunTime): 29.54 us | 0.0295 ms | 0.000030 s
OR-set remote add from the past + read on 5000 values(RunTime): 112.365 us | 0.1124 ms | 0.000112 s
OR-map remote put from the past + read on 1000 keys(RunTime): 64.3 us | 0.0643 ms | 0.000064 s
OR-map remote put from the past + read on 5000 keys(RunTime): 280.83 us | 0.2808 ms | 0.000281 s
Movable list remote move from the past + read on 1000 items(RunTime): 44.265 us | 0.0443 ms | 0.000044 s
Movable list remote move from the past + read on 5000 items(RunTime): 166.6 us | 0.1666 ms | 0.000167 s
Import 1000 chained changes(RunTime): 946.9750957854407 us | 0.9470 ms | 0.000947 s
Import 10000 chained changes(RunTime): 11516.119047619048 us | 11.5161 ms | 0.011516 s
exportChangesNewerThan on 50000 changes / 10 peers (99% caught-up)(RunTime): 1.5303968752179675 us | 0.0015 ms | 0.000002 s
takeSnapshot(pruneHistory) with 10000 changes(RunTime): 24129.1 us | 24.1291 ms | 0.024129 s
takeSnapshot(pruneHistory) with 100 concurrent heads(RunTime): 3832.984905660377 us | 3.8330 ms | 0.003833 s
Binary encode/decode 1000 changes(RunTime): 2375.309375 us | 2.3753 ms | 0.002375 s
Take snapshot with 1000 changes(RunTime): 130.41115 us | 0.1304 ms | 0.000130 s
CRDTTextHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 3029.76375 us | 3.0298 ms | 0.003030 s
CRDTTextHandler do 1000 operations and get value (incremental cache update: false)(RunTime): 2770.189705882353 us | 2.7702 ms | 0.002770 s
Import 1000 concurrent changes(RunTime): 983.644 us | 0.9836 ms | 0.000984 s
VersionVector toBytes 10 peers x1000(RunTime): 433.572 us | 0.4336 ms | 0.000434 s
VersionVector fromBytes 10 peers x1000(RunTime): 1439.0521428571428 us | 1.4391 ms | 0.001439 s
VersionVector intersection 10 peers x1000(RunTime): 186.39865067466266 us | 0.1864 ms | 0.000186 s
