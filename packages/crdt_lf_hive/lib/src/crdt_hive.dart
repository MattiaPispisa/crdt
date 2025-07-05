import 'package:hive/hive.dart';
import 'package:crdt_lf/crdt_lf.dart';
import 'package:hlc_dart/hlc_dart.dart';
import 'adapters/peer_id_adapter.dart';
import 'adapters/hybrid_logical_clock_adapter.dart';
import 'adapters/operation_id_adapter.dart';
import 'adapters/version_vector_adapter.dart';
import 'adapters/change_adapter.dart';
import 'adapters/snapshot_adapter.dart';

/// Main utility class for initializing Hive with CRDT adapters.
///
/// This class provides methods to initialize Hive with all the necessary
/// adapters for CRDT objects and to open the required boxes.
class CRDTHive {
  /// Initializes Hive with all CRDT adapters.
  ///
  /// This method must be called before using any CRDT objects with Hive.
  /// It registers all the necessary type adapters for:
  /// - [PeerId]
  /// - [HybridLogicalClock]
  /// - [OperationId]
  /// - [VersionVector]
  /// - [Change]
  /// - [Snapshot]
  static void initialize() {
    // Register all adapters
    Hive.registerAdapter(PeerIdAdapter());
    Hive.registerAdapter(HybridLogicalClockAdapter());
    Hive.registerAdapter(OperationIdAdapter());
    Hive.registerAdapter(VersionVectorAdapter());
    Hive.registerAdapter(ChangeAdapter());
    Hive.registerAdapter(SnapshotAdapter());
  }

  /// Opens the Changes box for storing [Change] objects.
  ///
  /// Returns a [Box] that can be used to store and retrieve [Change] objects.
  /// The box name defaults to 'changes' but can be customized.
  static Future<Box<Change>> openChangesBox({String boxName = 'changes'}) async {
    return await Hive.openBox<Change>(boxName);
  }

  /// Opens the Snapshots box for storing [Snapshot] objects.
  ///
  /// Returns a [Box] that can be used to store and retrieve [Snapshot] objects.
  /// The box name defaults to 'snapshots' but can be customized.
  static Future<Box<Snapshot>> openSnapshotsBox({String boxName = 'snapshots'}) async {
    return await Hive.openBox<Snapshot>(boxName);
  }

  /// Closes all CRDT-related boxes.
  ///
  /// This method closes all boxes that were opened for CRDT objects.
  /// It's useful for cleanup when shutting down the application.
  static Future<void> closeAllBoxes() async {
    await Hive.close();
  }

  /// Deletes a box from disk.
  ///
  /// This permanently deletes the specified box and all its data.
  /// Use with caution as this operation cannot be undone.
  static Future<void> deleteBox(String boxName) async {
    await Hive.deleteBoxFromDisk(boxName);
  }
} 