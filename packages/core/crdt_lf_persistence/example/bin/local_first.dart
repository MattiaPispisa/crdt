// ignore_for_file: avoid_print just for example

// A local-first note: no server, no database, one file.
//
// Run it twice. The first run starts from an empty note and appends a line;
// the second run reads back what the first one wrote.
//
//     dart run example/bin/local_first.dart "a line to append"
//
// Delete `note.crdt` to start over.
import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_persistence/crdt_lf_persistence.dart';
import 'package:crdt_lf_persistence/io.dart';

Future<void> main(List<String> arguments) async {
  // The file first: it knows which document it holds.
  final storage = await FileDocumentStorage.open('note.crdt');

  final document = CRDTDocument(documentId: storage.documentId);
  final text = CRDTFugueTextHandler(document, 'body');

  // Reads the file into the document, then follows it. Everything written
  // from here on is on disk within `writeDelay`.
  final persistence = await CRDTDocumentPersistence.open(document, storage);

  print('read back:\n${text.value.isEmpty ? '(empty)' : text.value}');

  final line = arguments.isEmpty ? 'hello 🌍' : arguments.join(' ');
  text.insert(text.value.length, '$line\n');

  // Writes what is still waiting. Without it the process could end before the
  // delayed write runs.
  await persistence.dispose();
  document.dispose();

  print('\nwrote: $line');
}
