// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:io';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_recipes/shared_outline/open_outline.dart';
import 'package:crdt_lf_recipes/shared_outline/outline.dart';
import 'package:crdt_socket_sync/replica.dart';
import 'package:crdt_socket_sync/web_socket_relay_server.dart';
import 'package:flutter_test/flutter_test.dart';

/// Waits until [done] holds.
Future<void> eventually(bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(done(), isTrue);
}

/// The whole outline of [replica], every reference resolved.
List<dynamic> outlineOf(CRDTReplica replica) {
  return chaptersOf(replica.document).resolved;
}

void main() {
  late Directory directory;
  late WebSocketRelayServer server;
  late String url;

  /// The file of one device.
  String fileOf(String device) => '${directory.path}/$device.db';

  setUp(() async {
    directory = Directory.systemTemp.createTempSync('shared_outline');
    server = WebSocketRelayServer(
      serverFactory: () => HttpServer.bind('localhost', 0),
    );
    await server.start();
    url = 'ws://localhost:${server.port}';
  });

  tearDown(() async {
    await server.dispose();
    directory.deleteSync(recursive: true);
  });

  test('a chapter reaches the other device, with its texts', () async {
    final phone = await openOutline(url, path: fileOf('phone'));
    final laptop = await openOutline(url, path: fileOf('laptop'));

    final intro = addChapter(chaptersOf(phone.document), 'Intro');
    intro.body.insert(0, 'Once upon a time');

    await eventually(() => outlineOf(laptop).isNotEmpty);
    await eventually(
      () => outlineOf(laptop).toString() == outlineOf(phone).toString(),
    );
    expect(outlineOf(laptop), [
      {'title': 'Intro', 'body': 'Once upon a time'},
    ]);

    // The laptop edits the chapter it received.
    chaptersOf(
      laptop.document,
    ).getRefAtAs<CRDTMapRefHandler>(0)!.title.insert(5, 'duction');
    await eventually(
      () => outlineOf(phone).toString() == outlineOf(laptop).toString(),
    );
    expect(outlineOf(phone), [
      {'title': 'Introduction', 'body': 'Once upon a time'},
    ]);

    await laptop.close();
    await phone.close();
  });

  test('the outline survives a restart, also after a compaction', () async {
    // Nothing listens on this port: the device is offline.
    final dead = await HttpServer.bind('localhost', 0);
    final offline = 'ws://localhost:${dead.port}';
    await dead.close();

    var phone = await openOutline(offline, path: fileOf('phone'));
    addChapter(chaptersOf(phone.document), 'Intro').body.insert(0, 'Hello');
    await phone.close();

    phone = await openOutline(offline, path: fileOf('phone'));
    expect(outlineOf(phone), [
      {'title': 'Intro', 'body': 'Hello'},
    ]);
    // A snapshot replaces the stored changes.
    await phone.persistence!.compact();
    await phone.close();

    phone = await openOutline(offline, path: fileOf('phone'));
    expect(outlineOf(phone), [
      {'title': 'Intro', 'body': 'Hello'},
    ]);
    addChapter(chaptersOf(phone.document), 'End');
    expect(outlineOf(phone), [
      {'title': 'Intro', 'body': 'Hello'},
      {'title': 'End', 'body': ''},
    ]);
    await phone.close();
  });
}
