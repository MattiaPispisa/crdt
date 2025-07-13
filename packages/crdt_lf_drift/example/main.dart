// ignore_for_file: avoid_print just for example

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_drift/crdt_lf_drift.dart';

Future<void> main() async {
  const changesToInsert = 3;
  final documentId = PeerId.parse('784ff372-6f0a-4fe9-8e63-19b72fd18c23');

  // Open storage for a document using Drift
  final changeStorage = await CRDTDrift.openChangeStorageForDocument(
    documentId.toString(),
    databasePath: './example/crdt_data',
  );

  final changesToSave = <Change>[];

  final document = CRDTDocument(peerId: documentId)
    // Load existing changes from Drift storage
    ..importChanges(await changeStorage.getChanges())
    // Listen for new local changes to save them
    ..localChanges.listen(changesToSave.add);

  final textHandler = CRDTTextHandler(document, 'text');

  print('Initial text: "${textHandler.value}"');

  // Make some changes
  for (var i = 0; i < changesToInsert; i++) {
    textHandler.insert(textHandler.length, 'Hello $i! ');
  }

  print('Text after changes: "${textHandler.value}"');
  print('${document.exportChanges().length} total changes');
  print('${changesToSave.length} new changes to save');

  // Save new changes to Drift database
  await changeStorage.saveChanges(changesToSave);
  print('Changes saved to Drift database');

  // Demonstrate reactive streams
  print('\nListening to change stream...');
  final changeStream = changeStorage.watchChanges();
  final subscription = changeStream.listen((changes) {
    print('Database has ${changes.length} changes for document');
  });

  // Make another change to trigger the stream
  await Future.delayed(Duration(milliseconds: 100));
  textHandler.insert(textHandler.length, 'Streaming! ');
  await changeStorage.saveChanges([changesToSave.last]);

  await Future.delayed(Duration(milliseconds: 100));
  
  // Clean up
  await subscription.cancel();
  await CRDTDrift.closeAllDatabases();
  print('\nDatabase closed');
} 