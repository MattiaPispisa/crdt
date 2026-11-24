// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
// The bridge is hidden from the public barrel on purpose.
// ignore: implementation_imports
import 'package:crdt_lf/src/document/document.dart' show DevToolsBridge;
import 'package:crdt_lf_devtools_extension/src/application/events/event_log_cubit.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/crdt_lf_client.dart';
import 'package:flutter_test/flutter_test.dart';

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

  test('a renewal never starts the log again after a stop', () async {
    final doc = CRDTDocument();
    addTearDown(doc.dispose);
    final id = (await client.documents()).single.id;
    final cubit = EventLogCubit(
      client,
      id,
      renewEvery: const Duration(milliseconds: 10),
    );
    addTearDown(cubit.close);
    await cubit.setRecording(recording: true);
    bridge.slow = 'eventsStop';

    await cubit.setRecording(recording: false);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(cubit.state.recording, isFalse);
    expect(await recording(), isFalse);
  });

  test('renews the lease of the log while recording', () async {
    final lease = DevToolsBridge.lease;
    DevToolsBridge.lease = const Duration(milliseconds: 200);
    addTearDown(() => DevToolsBridge.lease = lease);
    final doc = CRDTDocument();
    final text = CRDTTextHandler(doc, 'text');
    final id = (await client.documents()).single.id;
    final cubit = EventLogCubit(
      client,
      id,
      renewEvery: const Duration(milliseconds: 50),
    );
    addTearDown(cubit.close);

    await cubit.setRecording(recording: true);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    text.insert(0, 'a');
    await pumpEventQueue();
    expect(cubit.state.events, hasLength(1));
    expect(await recording(), isTrue);
  });

  test('a lease that ran out marks the events as missed', () async {
    final lease = DevToolsBridge.lease;
    DevToolsBridge.lease = const Duration(milliseconds: 100);
    addTearDown(() => DevToolsBridge.lease = lease);
    final doc = CRDTDocument();
    final text = CRDTTextHandler(doc, 'text');
    final id = (await client.documents()).single.id;
    final cubit = EventLogCubit(
      client,
      id,
      renewEvery: const Duration(milliseconds: 300),
    );
    addTearDown(cubit.close);
    await cubit.setRecording(recording: true);

    await Future<void>.delayed(const Duration(milliseconds: 150));
    // The first event after the lease: the app stops the log on it.
    text.insert(0, 'a');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(cubit.state.missed, isTrue);
    expect(await recording(), isTrue);

    cubit.clear();
    expect(cubit.state.missed, isFalse);
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

  test('stops a stale log at start and its own log at close', () async {
    final doc = CRDTDocument();
    final id = (await client.documents()).single.id;
    await client.eventsStart(id);

    final stale = EventLogCubit(client, id);
    await pumpEventQueue();
    expect(await recording(), isFalse);
    await stale.close();

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
