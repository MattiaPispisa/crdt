// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
// The bridge is hidden from the public barrel on purpose.
// ignore: implementation_imports
import 'package:crdt_lf/src/document/document.dart' show DevToolsBridge;
import 'package:crdt_lf_devtools_extension/src/application/handlers/handler_value_cubit.dart';
import 'package:crdt_lf_devtools_extension/src/application/load_status.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/crdt_lf_client.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/in_process_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

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

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 5));

  test('loads the selected value and reloads on a change', () async {
    final doc = CRDTDocument(documentId: 'd');
    final text = CRDTTextHandler(doc, 'text')..insert(0, 'hi');
    CRDTTextHandler(doc, 'other').insert(0, 'x');
    final id = (await client.documents()).single.id;
    final cubit = HandlerValueCubit(client, id, delay: Duration.zero);
    addTearDown(cubit.close);

    cubit.select('text');
    expect(cubit.state.status, LoadStatus.initial);
    await settle();
    expect(cubit.state.status, LoadStatus.loaded);
    expect(cubit.state.value?.value, 'hi');

    text.insert(2, '!');
    await settle();
    expect(cubit.state.value?.value, 'hi!');

    cubit.select('other');
    expect(cubit.state.value, isNull);
    await settle();
    expect(cubit.state.value?.value, 'x');

    cubit.select(null);
    await settle();
    expect(cubit.state.handler, isNull);
    expect(cubit.state.value, isNull);
  });

  test('a handler that is not open fails', () async {
    CRDTDocument(documentId: 'd');
    final id = (await client.documents()).single.id;
    final cubit = HandlerValueCubit(client, id, delay: Duration.zero)
      ..select('missing');
    addTearDown(cubit.close);
    await settle();
    expect(cubit.state.status, LoadStatus.failure);
    expect(cubit.state.error, contains('missing'));
  });
}
