Apply 1000 changes(RunTime): 963.4398268398269 us | 0.9634 ms | 0.000963 s
Change toBytes x1000(RunTime): 59.292425 us | 0.0593 ms | 0.000059 s
Change fromBytes x1000(RunTime): 19.13356951359632 us | 0.0191 ms | 0.000019 s
Change roundtrip x1000(RunTime): 80.58795 us | 0.0806 ms | 0.000081 s
DAG addNode chain of 1000(RunTime): 183.89220389805098 us | 0.1839 ms | 0.000184 s
DAG getAncestors chain of 200(RunTime): 7.4101746337131855 us | 0.0074 ms | 0.000007 s
CRDTFugueListHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 3082.3784615384616 us | 3.0824 ms | 0.003082 s
Fugue text takeSnapshot of 10000 elements (tombstones: false)(RunTime): 1082.9649214659687 us | 1.0830 ms | 0.001083 s
Fugue text restore of 10000 elements from snapshot (tombstones: false)(RunTime): 4322.567105263158 us | 4.3226 ms | 0.004323 s
Fugue text takeSnapshot of 10000 elements (tombstones: true)(RunTime): 3292.867123287671 us | 3.2929 ms | 0.003293 s
Fugue text restore of 10000 elements from snapshot (tombstones: true)(RunTime): 3487.8014492753623 us | 3.4878 ms | 0.003488 s
Fugue text takeSnapshot of 100000 elements (tombstones: false)(RunTime): 32406.93333333333 us | 32.4069 ms | 0.032407 s
Fugue text restore of 100000 elements from snapshot (tombstones: false)(RunTime): 95007.85 us | 95.0079 ms | 0.095008 s
Fugue text takeSnapshot of 100000 elements (tombstones: true)(RunTime): 68677.38 us | 68.6774 ms | 0.068677 s
Fugue text restore of 100000 elements from snapshot (tombstones: true)(RunTime): 61432.54285714285 us | 61.4325 ms | 0.061433 s
Fugue text keystroke + length on 30000 chars(RunTime): 2.995 us | 0.0030 ms | 0.000003 s
Fugue text keystroke + value on 30000 chars(RunTime): 619.33 us | 0.6193 ms | 0.000619 s
Fugue text update on 30000 chars(RunTime): 2.18 us | 0.0022 ms | 0.000002 s
FugueTree append 50000 elements(RunTime): 29905.371428571427 us | 29.9054 ms | 0.029905 s
FugueTree prepend 50000 elements(RunTime): 74679.63333333333 us | 74.6796 ms | 0.074680 s
FugueTree random insert 50000 elements(RunTime): 76518.33333333334 us | 76.5183 ms | 0.076518 s
FugueTree values() over 50000 live elements(RunTime): 857.8597457627118 us | 0.8579 ms | 0.000858 s
FugueTree values() over 50000 elements, 90% tombstones(RunTime): 139.22895 us | 0.1392 ms | 0.000139 s
HLC toUint8List x100k(RunTime): 25.21238573451783 us | 0.0252 ms | 0.000025 s
HLC fromUint8List x100k(RunTime): 507.14425 us | 0.5071 ms | 0.000507 s
HLC compareTo x100k(RunTime): 45.27376536312849 us | 0.0453 ms | 0.000045 s
CRDTListHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 2596.73625 us | 2.5967 ms | 0.002597 s
CRDTMapHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 2612.9924050632912 us | 2.6130 ms | 0.002613 s
Resolve nested tree with 50 leaves (cold caches)(RunTime): 195.09287856071964 us | 0.1951 ms | 0.000195 s
Resolve nested tree with 200 leaves (cold caches)(RunTime): 839.7036 us | 0.8397 ms | 0.000840 s
Resolve nested tree with 800 leaves (cold caches)(RunTime): 3578.8649122807014 us | 3.5789 ms | 0.003579 s
Import + resolve nested tree with 50 leaves (fresh peer)(RunTime): 550.8196 us | 0.5508 ms | 0.000551 s
Import + resolve nested tree with 200 leaves (fresh peer)(RunTime): 2234.9415254237288 us | 2.2349 ms | 0.002235 s
Import + resolve nested tree with 800 leaves (fresh peer)(RunTime): 10872.18275862069 us | 10.8722 ms | 0.010872 s
OpIdKey view x100k(RunTime): 482.26606741573033 us | 0.4823 ms | 0.000482 s
OpIdKey hashCode x100k (cold)(RunTime): 1981.3485436893202 us | 1.9813 ms | 0.001981 s
OpIdKey map lookup x10k(RunTime): 54.164175 us | 0.0542 ms | 0.000054 s
OperationId map lookup x10k(RunTime): 35.94580530973452 us | 0.0359 ms | 0.000036 s
CRDTORSetHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 2912.9211267605633 us | 2.9129 ms | 0.002913 s
PeerId generate x100(RunTime): 164.4147676161919 us | 0.1644 ms | 0.000164 s
PeerId toUint8List x1000(RunTime): 31.98432216905901 us | 0.0320 ms | 0.000032 s
PeerId fromUint8List x1000(RunTime): 58.760149999999996 us | 0.0588 ms | 0.000059 s
Fugue text remote keystroke + read on 2000 chars(RunTime): 61.165 us | 0.0612 ms | 0.000061 s
Fugue text remote keystroke + read on 10000 chars(RunTime): 184.435 us | 0.1844 ms | 0.000184 s
Fugue text remote keystroke + read on 30000 chars(RunTime): 670.925 us | 0.6709 ms | 0.000671 s
Text remote keystroke + read on 2000 chars(RunTime): 12.315 us | 0.0123 ms | 0.000012 s
Text remote keystroke + read on 10000 chars(RunTime): 13.47 us | 0.0135 ms | 0.000013 s
Text remote keystroke + read on 30000 chars(RunTime): 21.31 us | 0.0213 ms | 0.000021 s
Map remote set + read on 1000 keys(RunTime): 9.35 us | 0.0093 ms | 0.000009 s
Map remote set + read on 5000 keys(RunTime): 5.035 us | 0.0050 ms | 0.000005 s
OR-set remote add from the past + read on 1000 values(RunTime): 33.285 us | 0.0333 ms | 0.000033 s
OR-set remote add from the past + read on 5000 values(RunTime): 105.945 us | 0.1059 ms | 0.000106 s
OR-map remote put from the past + read on 1000 keys(RunTime): 77.385 us | 0.0774 ms | 0.000077 s
OR-map remote put from the past + read on 5000 keys(RunTime): 253.18 us | 0.2532 ms | 0.000253 s
Movable list remote move from the past + read on 1000 items(RunTime): 43.595 us | 0.0436 ms | 0.000044 s
Movable list remote move from the past + read on 5000 items(RunTime): 168.96 us | 0.1690 ms | 0.000169 s
Import 1000 chained changes(RunTime): 974.9931034482759 us | 0.9750 ms | 0.000975 s
Import 10000 chained changes(RunTime): 11605.418181818182 us | 11.6054 ms | 0.011605 s
exportChangesNewerThan on 50000 changes / 10 peers (99% caught-up)(RunTime): 1.594856 us | 0.0016 ms | 0.000002 s
takeSnapshot(pruneHistory) with 10000 changes(RunTime): 24763.22 us | 24.7632 ms | 0.024763 s
takeSnapshot(pruneHistory) with 100 concurrent heads(RunTime): 3884.656 us | 3.8847 ms | 0.003885 s
Binary encode/decode 1000 changes(RunTime): 2444.967088607595 us | 2.4450 ms | 0.002445 s
Take snapshot with 1000 changes(RunTime): 130.8464 us | 0.1308 ms | 0.000131 s
CRDTTextHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 3108.8118644067795 us | 3.1088 ms | 0.003109 s
CRDTTextHandler do 1000 operations and get value (incremental cache update: false)(RunTime): 2780.9365853658537 us | 2.7809 ms | 0.002781 s
Import 1000 concurrent changes(RunTime): 980.4638743455498 us | 0.9805 ms | 0.000980 s
VersionVector toBytes 10 peers x1000(RunTime): 426.54179999999997 us | 0.4265 ms | 0.000427 s
VersionVector fromBytes 10 peers x1000(RunTime): 1497.295652173913 us | 1.4973 ms | 0.001497 s
VersionVector intersection 10 peers x1000(RunTime): 183.70209895052474 us | 0.1837 ms | 0.000184 s
