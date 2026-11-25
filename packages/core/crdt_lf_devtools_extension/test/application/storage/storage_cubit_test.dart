// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
// The bridge is hidden from the public barrel on purpose.
// ignore: implementation_imports
import 'package:crdt_lf/src/document/document.dart' show DevToolsBridge;
import 'package:crdt_lf_devtools_extension/src/application/load_status.dart';
import 'package:crdt_lf_devtools_extension/src/application/storage/storage_cubit.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/crdt_lf_client.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/in_process_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/settle.dart';

void main() {
  late InProcessBridge bridge;
  late CrdtLfClient client;

  setUp(() {
    DevToolsBridge.reset();
    bridge = InProcessBridge();
    client = CrdtLfClient(bridge);
  });

  tearDown(() {
    bridge.dispose();
    DevToolsBridge.reset();
  });

  test(
    'reloads on a snapshot, sorts entries and marks missing formats',
    () async {
      final remote = CRDTDocument(documentId: 'd');
      CRDTListHandler<int>(
        remote,
        'list',
        handlerType: 'app/ints',
      ).insert(0, 1);
      final doc = CRDTDocument(documentId: 'd')
        ..importChanges(remote.exportChanges());
      remote.dispose();
      CRDTTextHandler(doc, 'text').insert(0, 'a long enough text');

      final cubit = StorageCubit(
        client,
        (await client.documents()).single.id,
        delay: Duration.zero,
      );
      addTearDown(cubit.close);
      await settle();
      expect(cubit.state.status, LoadStatus.loaded);
      expect(cubit.state.snapshot!.snapshot, isNull);
      expect(cubit.state.entriesBySize, isEmpty);

      doc.takeSnapshot();
      await settle();
      final snapshot = cubit.state.snapshot!.snapshot!;
      expect(cubit.state.detail!.summary.snapshotId, snapshot.id);
      final sizes = cubit.state.entriesBySize.map((e) => e.bytes).toList();
      expect(sizes, [...sizes]..sort((a, b) => b.compareTo(a)));

      final formats = {for (final row in cubit.state.formats) row.type: row};
      expect(formats['CRDTTextHandler']!.missing, isFalse);
      expect(formats['app/ints']!.missing, isTrue);
      expect(formats['app/ints']!.reads, isNull);
    },
  );

  test('a failed load reports the error', () async {
    final cubit = StorageCubit(client, 42, delay: Duration.zero);
    addTearDown(cubit.close);
    await settle();
    expect(cubit.state.status, LoadStatus.failure);
    expect(cubit.state.error, contains('42'));
  });
}
