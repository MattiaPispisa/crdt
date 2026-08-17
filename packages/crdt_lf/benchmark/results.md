Apply 1000 changes(RunTime): 954.6498084291188 us | 0.9546 ms | 0.000955 s
Change toBytes x1000(RunTime): 58.83505 us | 0.0588 ms | 0.000059 s
Change fromBytes x1000(RunTime): 18.841268494958065 us | 0.0188 ms | 0.000019 s
Change roundtrip x1000(RunTime): 79.310425 us | 0.0793 ms | 0.000079 s
DAG addNode chain of 1000(RunTime): 182.03875562218892 us | 0.1820 ms | 0.000182 s
DAG getAncestors chain of 200(RunTime): 7.671143488200876 us | 0.0077 ms | 0.000008 s
CRDTFugueListHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 3096.740625 us | 3.0967 ms | 0.003097 s
Fugue text snapshot of 10000 elements (tombstones: false)(Size): 10044 bytes handler blob | 10144 bytes total
Fugue text takeSnapshot of 10000 elements (tombstones: false)(RunTime): 1075.1748691099476 us | 1.0752 ms | 0.001075 s
Fugue text restore of 10000 elements from snapshot (tombstones: false)(RunTime): 4411.380882352942 us | 4.4114 ms | 0.004411 s
Fugue text snapshot of 10000 elements (tombstones: true)(Size): 109959 bytes handler blob | 110060 bytes total
Fugue text takeSnapshot of 10000 elements (tombstones: true)(RunTime): 3431.1160000000004 us | 3.4311 ms | 0.003431 s
Fugue text restore of 10000 elements from snapshot (tombstones: true)(RunTime): 3740.4507246376807 us | 3.7405 ms | 0.003740 s
Fugue text snapshot of 100000 elements (tombstones: false)(Size): 100047 bytes handler blob | 100148 bytes total
Fugue text takeSnapshot of 100000 elements (tombstones: false)(RunTime): 34634.6 us | 34.6346 ms | 0.034635 s
Fugue text restore of 100000 elements from snapshot (tombstones: false)(RunTime): 82894.9 us | 82.8949 ms | 0.082895 s
Fugue text snapshot of 100000 elements (tombstones: true)(Size): 1141769 bytes handler blob | 1141870 bytes total
Fugue text takeSnapshot of 100000 elements (tombstones: true)(RunTime): 96583.12 us | 96.5831 ms | 0.096583 s
Fugue text restore of 100000 elements from snapshot (tombstones: true)(RunTime): 52264.08333333333 us | 52.2641 ms | 0.052264 s
Movable list snapshot of 10000 elements(Size): 922400 bytes handler blob | 922504 bytes total | 92.2 bytes per element
Fugue text keystroke + length on 30000 chars(RunTime): 3.08 us | 0.0031 ms | 0.000003 s
Fugue text keystroke + value on 30000 chars(RunTime): 625.125 us | 0.6251 ms | 0.000625 s
Fugue text update on 30000 chars(RunTime): 2.23 us | 0.0022 ms | 0.000002 s
FugueTree append 50000 elements(RunTime): 29551.185714285715 us | 29.5512 ms | 0.029551 s
FugueTree prepend 50000 elements(RunTime): 72578.73333333334 us | 72.5787 ms | 0.072579 s
FugueTree random insert 50000 elements(RunTime): 76139.26666666666 us | 76.1393 ms | 0.076139 s
FugueTree values() over 50000 live elements(RunTime): 843.2338983050847 us | 0.8432 ms | 0.000843 s
FugueTree values() over 50000 elements, 90% tombstones(RunTime): 126.38905 us | 0.1264 ms | 0.000126 s
Fugue text retained RSS for 10000 elements(Size): 10289152 bytes (before: 210599936, after: 220889088)
Fugue text retained RSS for 100000 elements(Size): 91799552 bytes (before: 220905472, after: 312705024)
HLC toUint8List x100k(RunTime): 24.93750779593364 us | 0.0249 ms | 0.000025 s
HLC fromUint8List x100k(RunTime): 511.69575000000003 us | 0.5117 ms | 0.000512 s
HLC compareTo x100k(RunTime): 45.44184062850729 us | 0.0454 ms | 0.000045 s
CRDTListHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 2596.706578947368 us | 2.5967 ms | 0.002597 s
CRDTMapHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 2615.266233766234 us | 2.6153 ms | 0.002615 s
Resolve nested tree with 50 leaves (cold caches)(RunTime): 190.2586956521739 us | 0.1903 ms | 0.000190 s
Resolve nested tree with 200 leaves (cold caches)(RunTime): 815.3244 us | 0.8153 ms | 0.000815 s
Resolve nested tree with 800 leaves (cold caches)(RunTime): 3491.1966101694916 us | 3.4912 ms | 0.003491 s
Import + resolve nested tree with 50 leaves (fresh peer)(RunTime): 538.709375 us | 0.5387 ms | 0.000539 s
Import + resolve nested tree with 200 leaves (fresh peer)(RunTime): 2007.732110091743 us | 2.0077 ms | 0.002008 s
Import + resolve nested tree with 800 leaves (fresh peer)(RunTime): 10048.020833333332 us | 10.0480 ms | 0.010048 s
OpIdKey view x100k(RunTime): 475.0173033707865 us | 0.4750 ms | 0.000475 s
OpIdKey hashCode x100k (cold)(RunTime): 1975.9796116504854 us | 1.9760 ms | 0.001976 s
OpIdKey map lookup x10k(RunTime): 53.870075 us | 0.0539 ms | 0.000054 s
OperationId map lookup x10k(RunTime): 35.160028198801555 us | 0.0352 ms | 0.000035 s
CRDTORSetHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 3003.64126984127 us | 3.0036 ms | 0.003004 s
PeerId generate x100(RunTime): 163.32443778110945 us | 0.1633 ms | 0.000163 s
PeerId toUint8List x1000(RunTime): 32.08107847857487 us | 0.0321 ms | 0.000032 s
PeerId fromUint8List x1000(RunTime): 59.57385000000001 us | 0.0596 ms | 0.000060 s
Fugue text remote keystroke + read on 2000 chars(RunTime): 61.785 us | 0.0618 ms | 0.000062 s
Fugue text remote keystroke + read on 10000 chars(RunTime): 185.86 us | 0.1859 ms | 0.000186 s
Fugue text remote keystroke + read on 30000 chars(RunTime): 674.655 us | 0.6747 ms | 0.000675 s
Text remote keystroke + read on 2000 chars(RunTime): 9.255 us | 0.0093 ms | 0.000009 s
Text remote keystroke + read on 10000 chars(RunTime): 13.5 us | 0.0135 ms | 0.000013 s
Text remote keystroke + read on 30000 chars(RunTime): 26.65 us | 0.0267 ms | 0.000027 s
Map remote set + read on 1000 keys(RunTime): 8.9 us | 0.0089 ms | 0.000009 s
Map remote set + read on 5000 keys(RunTime): 14.67 us | 0.0147 ms | 0.000015 s
OR-set remote add from the past + read on 1000 values(RunTime): 29.605 us | 0.0296 ms | 0.000030 s
OR-set remote add from the past + read on 5000 values(RunTime): 116.745 us | 0.1167 ms | 0.000117 s
OR-map remote put from the past + read on 1000 keys(RunTime): 65.175 us | 0.0652 ms | 0.000065 s
OR-map remote put from the past + read on 5000 keys(RunTime): 249.405 us | 0.2494 ms | 0.000249 s
Movable list remote move from the past + read on 1000 items(RunTime): 43.53 us | 0.0435 ms | 0.000044 s
Movable list remote move from the past + read on 5000 items(RunTime): 164.04 us | 0.1640 ms | 0.000164 s
Import 1000 chained changes(RunTime): 987.9314741035856 us | 0.9879 ms | 0.000988 s
Import 10000 chained changes(RunTime): 11719.909523809523 us | 11.7199 ms | 0.011720 s
exportChangesNewerThan on 50000 changes / 10 peers (99% caught-up)(RunTime): 1.5472910030767324 us | 0.0015 ms | 0.000002 s
takeSnapshot(pruneHistory) with 10000 changes(RunTime): 24314.65 us | 24.3147 ms | 0.024315 s
takeSnapshot(pruneHistory) with 100 concurrent heads(RunTime): 3878.0442307692306 us | 3.8780 ms | 0.003878 s
Binary encode/decode 1000 changes(RunTime): 2472.304 us | 2.4723 ms | 0.002472 s
Take snapshot with 1000 changes(RunTime): 128.78419654714475 us | 0.1288 ms | 0.000129 s
CRDTTextHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 2965.2256097560976 us | 2.9652 ms | 0.002965 s
CRDTTextHandler do 1000 operations and get value (incremental cache update: false)(RunTime): 2903.107894736842 us | 2.9031 ms | 0.002903 s
Import 1000 concurrent changes(RunTime): 978.7008 us | 0.9787 ms | 0.000979 s
VersionVector toBytes 10 peers x1000(RunTime): 432.918 us | 0.4329 ms | 0.000433 s
VersionVector fromBytes 10 peers x1000(RunTime): 1402.6734265734265 us | 1.4027 ms | 0.001403 s
VersionVector intersection 10 peers x1000(RunTime): 187.86424287856073 us | 0.1879 ms | 0.000188 s
