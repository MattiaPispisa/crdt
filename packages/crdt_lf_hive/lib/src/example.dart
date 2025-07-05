import 'package:crdt_lf/crdt_lf.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'package:crdt_lf_hive/crdt_lf_hive.dart';

/// Example showing how to use CRDT Hive library.
/// 
/// This example demonstrates:
/// 1. Initializing Hive with CRDT adapters
/// 2. Creating and storing Change and Snapshot objects
/// 3. Retrieving and managing stored objects
Future<void> main() async {
  print('CRDT Hive Example');
  print('=================');

  // 1. Initialize Hive with CRDT adapters
  print('\n1. Initializing Hive...');
  CRDTHive.initialize();
  print('   ✓ All CRDT adapters registered');

  // 2. Open storage boxes
  print('\n2. Opening storage boxes...');
  final changesBox = await CRDTHive.openChangesBox();
  final snapshotsBox = await CRDTHive.openSnapshotsBox();
  
  final changeStorage = CRDTChangeStorage(changesBox);
  final snapshotStorage = CRDTSnapshotStorage(snapshotsBox);
  print('   ✓ Boxes opened successfully');

  // 3. Create sample CRDT objects
  print('\n3. Creating sample CRDT objects...');
  
  final peerId = PeerId.generate();
  final hlc = HybridLogicalClock.now();
  final operationId = OperationId(peerId, hlc);
  
  // Create a sample Change
  final change = Change.fromPayload(
    id: operationId,
    deps: <OperationId>{},
    hlc: hlc,
    author: peerId,
    payload: {
      'type': 'text_insert',
      'text': 'Hello CRDT!',
      'position': 0,
    },
  );
  print('   ✓ Created Change: ${change.id}');

  // Create a sample VersionVector and Snapshot
  final versionVector = VersionVector({peerId: hlc});
  final snapshot = Snapshot(
    id: 'snapshot_1',
    versionVector: versionVector,
    data: {
      'text': 'Hello CRDT!',
      'metadata': {
        'created_at': DateTime.now().toIso8601String(),
        'author': peerId.toString(),
      }
    },
  );
  print('   ✓ Created Snapshot: ${snapshot.id}');

  // 4. Store objects
  print('\n4. Storing objects...');
  await changeStorage.saveChange(change);
  print('   ✓ Change stored with key: ${change.id}');
  
  await snapshotStorage.saveSnapshot(snapshot);
  print('   ✓ Snapshot stored with key: ${snapshot.id}');

  // 5. Retrieve objects
  print('\n5. Retrieving objects...');
  
  final retrievedChange = changeStorage.getChange(operationId);
  if (retrievedChange != null) {
    print('   ✓ Retrieved Change: ${retrievedChange.id}');
    print('     Payload: ${retrievedChange.payload}');
  }
  
  final retrievedSnapshot = snapshotStorage.getSnapshot(snapshot.id);
  if (retrievedSnapshot != null) {
    print('   ✓ Retrieved Snapshot: ${retrievedSnapshot.id}');
    print('     Data keys: ${retrievedSnapshot.data.keys.join(', ')}');
  }

  // 6. Query operations
  print('\n6. Performing queries...');
  
  final allChanges = changeStorage.getAllChanges();
  print('   ✓ Total changes in storage: ${allChanges.length}');
  
  final changesByAuthor = changeStorage.getChangesByAuthor(peerId);
  print('   ✓ Changes by author $peerId: ${changesByAuthor.length}');
  
  final allSnapshots = snapshotStorage.getAllSnapshots();
  print('   ✓ Total snapshots in storage: ${allSnapshots.length}');

  // 7. Storage statistics
  print('\n7. Storage statistics...');
  print('   Changes count: ${changeStorage.count}');
  print('   Snapshots count: ${snapshotStorage.count}');
  print('   Changes box keys: ${changeStorage.keys.take(3).join(', ')}${changeStorage.count > 3 ? '...' : ''}');
  print('   Snapshots box keys: ${snapshotStorage.keys.take(3).join(', ')}${snapshotStorage.count > 3 ? '...' : ''}');

  // 8. Create multiple objects for batch operations
  print('\n8. Testing batch operations...');
  
  final moreChanges = <Change>[];
  for (int i = 0; i < 3; i++) {
    final newHlc = HybridLogicalClock.now();
    newHlc.localEvent(DateTime.now().millisecondsSinceEpoch + i);
    
    final newOpId = OperationId(peerId, newHlc);
    final newChange = Change.fromPayload(
      id: newOpId,
      deps: {operationId}, // Depends on previous change
      hlc: newHlc,
      author: peerId,
      payload: {
        'type': 'text_insert',
        'text': ' Change $i',
        'position': 11 + i * 9,
      },
    );
    moreChanges.add(newChange);
  }
  
  await changeStorage.saveChanges(moreChanges);
  print('   ✓ Saved ${moreChanges.length} changes in batch');
  
  final sortedChanges = changeStorage.getChangesSortedByTime();
  print('   ✓ Changes sorted by time: ${sortedChanges.length} total');

  // 9. Time range queries
  print('\n9. Testing time range queries...');
  
  final firstChange = changeStorage.getOldestChange();
  final lastChange = changeStorage.getMostRecentChange();
  
  if (firstChange != null && lastChange != null) {
    final changesInRange = changeStorage.getChangesInTimeRange(
      from: firstChange.hlc,
      to: lastChange.hlc,
    );
    print('   ✓ Changes in time range: ${changesInRange.length}');
  }

  // 10. Cleanup demonstration
  print('\n10. Cleanup demonstration...');
  print('    Before cleanup - Changes: ${changeStorage.count}, Snapshots: ${snapshotStorage.count}');
  
  // Note: In a real application, you might want to keep the data
  await changeStorage.clear();
  await snapshotStorage.clear();
  
  print('    After cleanup - Changes: ${changeStorage.count}, Snapshots: ${snapshotStorage.count}');
  print('   ✓ Storage cleared');

  // 11. Close boxes
  print('\n11. Closing storage...');
  await CRDTHive.closeAllBoxes();
  print('   ✓ All boxes closed');

  print('\n✅ Example completed successfully!');
  print('\nThis example showed how to:');
  print('  • Initialize Hive with CRDT adapters');
  print('  • Store and retrieve Change and Snapshot objects');
  print('  • Use storage utilities for common operations');
  print('  • Perform queries and batch operations');
  print('  • Manage storage lifecycle');
} 