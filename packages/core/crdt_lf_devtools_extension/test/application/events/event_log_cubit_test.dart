// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
// The bridge is hidden from the public barrel on purpose.
// ignore: implementation_imports
import 'package:crdt_lf/src/document/document.dart' show DevToolsBridge;
import 'package:crdt_lf_devtools_extension/src/application/events/event_log_cubit.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/crdt_lf_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_time.dart';
import '../../helpers/slow_bridge.dart';

void main() {
  late SlowBridge bridge;
  late CrdtLfClient client;

  setUp(() {
    DevToolsBridge.reset();
    bridge = SlowBridge();
    client = CrdtLfClient(bridge);
  });

  tearDown(() {
    bridge.dispose();
    DevToolsBridge.reset();
  });

  Future<bool> recording() async => (await client.documents()).single.recording;

  testOnFakeTime('a renewal never starts the log again after a stop', (
    tester,
  ) async {
    final doc = CRDTDocument();
    addTearDown(doc.dispose);
    final id = (await client.documents()).single.id;
    final cubit = EventLogCubit(
      client,
      id,
      renewEvery: const Duration(milliseconds: 10),
    );
    await cubit.setRecording(recording: true);
    bridge.slow = 'eventsStop';

    unawaited(cubit.setRecording(recording: false));
    // Past the late answer, and past many renewals.
    await tester.pump(const Duration(seconds: 1));
    expect(cubit.state.recording, isFalse);
    expect(await recording(), isFalse);
    unawaited(cubit.close());
  });

  testOnFakeTime('renews the lease of the log while recording', (tester) async {
    final doc = CRDTDocument();
    final text = CRDTTextHandler(doc, 'text');
    final id = (await client.documents()).single.id;
    final cubit = EventLogCubit(client, id);

    await cubit.setRecording(recording: true);
    await tester.pump(DevToolsBridge.lease * 3);
    text.insert(0, 'a');
    await tester.pump();
    expect(cubit.state.events, hasLength(1));
    expect(await recording(), isTrue);
    unawaited(cubit.close());
  });

  testOnFakeTime('a lease that ran out marks the events as missed', (
    tester,
  ) async {
    final doc = CRDTDocument();
    final text = CRDTTextHandler(doc, 'text');
    final id = (await client.documents()).single.id;
    final cubit = EventLogCubit(
      client,
      id,
      renewEvery: DevToolsBridge.lease * 2,
    );
    await cubit.setRecording(recording: true);

    await tester.pump(DevToolsBridge.lease);
    // The first event after the lease: the app stops the log on it.
    text.insert(0, 'a');
    await tester.pump();
    expect(await recording(), isFalse);
    await tester.pump(DevToolsBridge.lease);
    expect(cubit.state.missed, isTrue);
    expect(await recording(), isTrue);

    await cubit.setRecording(recording: false);
    expect(cubit.state.missed, isTrue);
    await cubit.setRecording(recording: true);
    expect(cubit.state.missed, isFalse);
    unawaited(cubit.close());
  });

  test('records newest first, keeps the cap, clears and stops', () async {
    final doc = CRDTDocument();
    final text = CRDTTextHandler(doc, 'text');
    final id = (await client.documents()).single.id;
    final cubit = EventLogCubit(client, id);
    addTearDown(cubit.close);

    text.insert(0, 'a');
    await pumpEventQueue();
    expect(cubit.state.events, isEmpty);

    await cubit.setRecording(recording: true);
    expect(cubit.state.recording, isTrue);
    expect(await recording(), isTrue);
    for (var i = 0; i < EventLogCubit.maxEvents + 1; i++) {
      text.insert(0, 'b');
    }
    doc.takeSnapshot();
    await pumpEventQueue();
    final events = cubit.state.events;
    expect(events, hasLength(EventLogCubit.maxEvents));
    // A snapshot also prunes the history it folds.
    expect(events.map((e) => e.type).take(3), [
      'pruned',
      'snapshot',
      'changes',
    ]);
    expect(events[1].reason, 'taken');
    expect(events[2].source, 'created');
    expect(events[1].n, greaterThan(events[2].n));

    cubit.select(events[1].n);
    expect(cubit.state.selected, events[1]);
    text.insert(0, 'c');
    await pumpEventQueue();
    expect(cubit.state.selected, events[1]);

    cubit.clear();
    expect(cubit.state.events, isEmpty);
    expect(cubit.state.selected, isNull);

    await cubit.setRecording(recording: false);
    expect(await recording(), isFalse);
    text.insert(0, 'd');
    await pumpEventQueue();
    expect(cubit.state.events, isEmpty);
  });

  test('leaves a log it did not start, and stops its own at close', () async {
    final doc = CRDTDocument();
    final id = (await client.documents()).single.id;
    // Another DevTools window records.
    await client.eventsStart(id);

    final other = EventLogCubit(client, id);
    await pumpEventQueue();
    expect(other.state.recording, isFalse);
    expect(await recording(), isTrue);
    await other.close();
    await pumpEventQueue();
    expect(await recording(), isTrue);
    await client.eventsStop(id);

    final cubit = EventLogCubit(client, id);
    await cubit.setRecording(recording: true);
    expect(await recording(), isTrue);
    await cubit.close();
    await pumpEventQueue();
    expect(await recording(), isFalse);

    doc.dispose();
  });

  test('a failed call reports the error', () async {
    final cubit = EventLogCubit(client, 42);
    addTearDown(cubit.close);
    await cubit.setRecording(recording: true);
    expect(cubit.state.recording, isFalse);
    expect(cubit.state.error, contains('42'));
  });
}
