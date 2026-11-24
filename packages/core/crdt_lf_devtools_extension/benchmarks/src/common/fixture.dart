// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
// The bridge is hidden from the public barrel on purpose.
// ignore: implementation_imports
import 'package:crdt_lf/src/document/document.dart' show DevToolsBridge;
import 'package:crdt_lf_devtools_extension/src/bridge/crdt_lf_client.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/in_process_bridge.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/models/json.dart';

/// A document whose map handler `map` holds [changes] keys, one change
/// each.
CRDTDocument mapDocument(int changes, {String? documentId}) {
  final doc = CRDTDocument(documentId: documentId);
  final map = CRDTMapHandler<int>(doc, 'map', handlerType: 'int map');
  for (var i = 0; i < changes; i++) {
    map.set('k$i', i);
  }
  return doc;
}

var _edits = 0;

/// One more change on the `map` handler of [doc].
void edit(CRDTDocument doc) =>
    (doc.handlerById('map')! as CRDTMapHandler<int>).set('e${_edits++}', 0);

/// The extension side of the bridge, on the documents of this isolate.
class Extension {
  Extension([InProcessBridge? bridge]) : bridge = bridge ?? InProcessBridge() {
    client = CrdtLfClient(this.bridge);
  }

  final InProcessBridge bridge;

  late final CrdtLfClient client;

  /// The tracked id of [doc].
  Future<int> idOf(CRDTDocument doc) async =>
      (await client.documents())
          .firstWhere((d) => d.documentId == doc.documentId)
          .id;

  void dispose() => bridge.dispose();
}

/// An [InProcessBridge] that runs [before] ahead of each call to [method].
class HookedBridge extends InProcessBridge {
  HookedBridge(this.method, this.before);

  final String method;

  void Function()? before;

  @override
  Future<Json> call(String method, [Map<String, String> params = const {}]) {
    if (method == this.method) before?.call();
    return super.call(method, params);
  }
}

/// Forgets every document the bridge tracks.
void resetBridge() => DevToolsBridge.reset();

/// Lets the bridge events, the zero-delay gates and the loads they start
/// run.
Future<void> settle() async {
  for (var i = 0; i < 3; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
