Apply 1000 changes(RunTime): 9828.101123595505 us | 9.8281 ms | 0.009828 s
Change toBytes x1000(RunTime): 599.88925 us | 0.5999 ms | 0.000600 s
Change fromBytes x1000(RunTime): 192.44623758594346 us | 0.1924 ms | 0.000192 s
Change roundtrip x1000(RunTime): 796.29925 us | 0.7963 ms | 0.000796 s
DAG addNode chain of 1000(RunTime): 1851.9835082458771 us | 1.8520 ms | 0.001852 s
DAG getAncestors chain of 200(RunTime): 79.28543604420065 us | 0.0793 ms | 0.000079 s
CRDTFugueListHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 32084.63888888889 us | 32.0846 ms | 0.032085 s
Fugue text snapshot of 10000 elements (tombstones: false)(Size): 10044 bytes handler blob | 10144 bytes total
Fugue text takeSnapshot of 10000 elements (tombstones: false)(RunTime): 10655.204188481675 us | 10.6552 ms | 0.010655 s
Fugue text restore of 10000 elements from snapshot (tombstones: false)(RunTime): 41748.74545454545 us | 41.7487 ms | 0.041749 s
Fugue text snapshot of 10000 elements (tombstones: true)(Size): 109959 bytes handler blob | 110060 bytes total
Fugue text takeSnapshot of 10000 elements (tombstones: true)(RunTime): 30652.15068493151 us | 30.6522 ms | 0.030652 s
Fugue text restore of 10000 elements from snapshot (tombstones: true)(RunTime): 46243.1 us | 46.2431 ms | 0.046243 s
Fugue text snapshot of 100000 elements (tombstones: false)(Size): 100047 bytes handler blob | 100148 bytes total
Fugue text takeSnapshot of 100000 elements (tombstones: false)(RunTime): 300578.9 us | 300.5789 ms | 0.300579 s
Fugue text restore of 100000 elements from snapshot (tombstones: false)(RunTime): 814103.2 us | 814.1032 ms | 0.814103 s
Fugue text snapshot of 100000 elements (tombstones: true)(Size): 1141769 bytes handler blob | 1141870 bytes total
Fugue text takeSnapshot of 100000 elements (tombstones: true)(RunTime): 954210.8 us | 954.2108 ms | 0.954211 s
Fugue text restore of 100000 elements from snapshot (tombstones: true)(RunTime): 484441.6666666667 us | 484.4417 ms | 0.484442 s
Fugue text keystroke + length on 30000 chars(RunTime): 82.66885964912281 us | 0.0827 ms | 0.000083 s
Fugue text keystroke + value on 30000 chars(RunTime): 7733.314606741573 us | 7.7333 ms | 0.007733 s
Fugue text update on 30000 chars(RunTime): 35.58353391526259 us | 0.0356 ms | 0.000036 s
FugueTree append 50000 elements(RunTime): 313518.85714285716 us | 313.5189 ms | 0.313519 s
FugueTree prepend 50000 elements(RunTime): 740614.6666666666 us | 740.6147 ms | 0.740615 s
FugueTree random insert 50000 elements(RunTime): 762142.0 us | 762.1420 ms | 0.762142 s
FugueTree values() over 50000 live elements(RunTime): 8692.6 us | 8.6926 ms | 0.008693 s
FugueTree values() over 50000 elements, 90% tombstones(RunTime): 1334.352 us | 1.3344 ms | 0.001334 s
Fugue text retained RSS for 10000 elements(Size): 9650176 bytes (before: 209354752, after: 219004928)
Fugue text retained RSS for 100000 elements(Size): 90193920 bytes (before: 219021312, after: 309215232)
HLC toUint8List x100k(RunTime): 250.47070941161323 us | 0.2505 ms | 0.000250 s
HLC fromUint8List x100k(RunTime): 5089.4425 us | 5.0894 ms | 0.005089 s
HLC compareTo x100k(RunTime): 466.8481981981982 us | 0.4668 ms | 0.000467 s
CRDTListHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 26416.657894736843 us | 26.4167 ms | 0.026417 s
CRDTMapHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 27340.31168831169 us | 27.3403 ms | 0.027340 s
Resolve nested tree with 50 leaves (cold caches)(RunTime): 2002.519 us | 2.0025 ms | 0.002003 s
Resolve nested tree with 200 leaves (cold caches)(RunTime): 8622.254237288136 us | 8.6223 ms | 0.008622 s
Resolve nested tree with 800 leaves (cold caches)(RunTime): 35500.293103448275 us | 35.5003 ms | 0.035500 s
Import + resolve nested tree with 50 leaves (fresh peer)(RunTime): 5507.359820089955 us | 5.5074 ms | 0.005507 s
Import + resolve nested tree with 200 leaves (fresh peer)(RunTime): 22517.398305084746 us | 22.5174 ms | 0.022517 s
Import + resolve nested tree with 800 leaves (fresh peer)(RunTime): 92350.6551724138 us | 92.3507 ms | 0.092351 s
OpIdKey view x100k(RunTime): 4753.36404494382 us | 4.7534 ms | 0.004753 s
OpIdKey hashCode x100k (cold)(RunTime): 19749.47 us | 19.7495 ms | 0.019749 s
OpIdKey map lookup x10k(RunTime): 529.0265 us | 0.5290 ms | 0.000529 s
OperationId map lookup x10k(RunTime): 354.38659793814435 us | 0.3544 ms | 0.000354 s
CRDTORSetHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 29961.709677419356 us | 29.9617 ms | 0.029962 s
PeerId generate x100(RunTime): 1640.920539730135 us | 1.6409 ms | 0.001641 s
PeerId toUint8List x1000(RunTime): 316.4717665615142 us | 0.3165 ms | 0.000316 s
PeerId fromUint8List x1000(RunTime): 586.19 us | 0.5862 ms | 0.000586 s
Fugue text remote keystroke + read on 2000 chars(RunTime): 76.855 us | 0.0769 ms | 0.000077 s
Fugue text remote keystroke + read on 10000 chars(RunTime): 240.01 us | 0.2400 ms | 0.000240 s
Fugue text remote keystroke + read on 30000 chars(RunTime): 786.2 us | 0.7862 ms | 0.000786 s
Text remote keystroke + read on 2000 chars(RunTime): 9.56 us | 0.0096 ms | 0.000010 s
Text remote keystroke + read on 10000 chars(RunTime): 13.925 us | 0.0139 ms | 0.000014 s
Text remote keystroke + read on 30000 chars(RunTime): 22.24 us | 0.0222 ms | 0.000022 s
Map remote set + read on 1000 keys(RunTime): 9.475 us | 0.0095 ms | 0.000009 s
Map remote set + read on 5000 keys(RunTime): 5.385 us | 0.0054 ms | 0.000005 s
OR-set remote add from the past + read on 1000 values(RunTime): 29.75 us | 0.0297 ms | 0.000030 s
OR-set remote add from the past + read on 5000 values(RunTime): 100.33 us | 0.1003 ms | 0.000100 s
OR-map remote put from the past + read on 1000 keys(RunTime): 70.225 us | 0.0702 ms | 0.000070 s
OR-map remote put from the past + read on 5000 keys(RunTime): 251.94 us | 0.2519 ms | 0.000252 s
Import 1000 chained changes(RunTime): 9321.011494252874 us | 9.3210 ms | 0.009321 s
Import 10000 chained changes(RunTime): 119140.0 us | 119.1400 ms | 0.119140 s
exportChangesNewerThan on 50000 changes / 10 peers (99% caught-up)(RunTime): 15.324777382530051 us | 0.0153 ms | 0.000015 s
takeSnapshot(pruneHistory) with 10000 changes(RunTime): 239794.7 us | 239.7947 ms | 0.239795 s
takeSnapshot(pruneHistory) with 100 concurrent heads(RunTime): 38112.903846153844 us | 38.1129 ms | 0.038113 s
Binary encode/decode 1000 changes(RunTime): 24553.012987012986 us | 24.5530 ms | 0.024553 s
Take snapshot with 1000 changes(RunTime): 1297.1365 us | 1.2971 ms | 0.001297 s
CRDTTextHandler do 1000 operations and get value (incremental cache update: true)(RunTime): 29810.764705882353 us | 29.8108 ms | 0.029811 s
CRDTTextHandler do 1000 operations and get value (incremental cache update: false)(RunTime): 29102.54054054054 us | 29.1025 ms | 0.029103 s
Import 1000 concurrent changes(RunTime): 9463.655430711611 us | 9.4637 ms | 0.009464 s
VersionVector toBytes 10 peers x1000(RunTime): 4327.742 us | 4.3277 ms | 0.004328 s
VersionVector fromBytes 10 peers x1000(RunTime): 14499.644927536232 us | 14.4996 ms | 0.014500 s
VersionVector intersection 10 peers x1000(RunTime): 1797.2901049475263 us | 1.7973 ms | 0.001797 s
