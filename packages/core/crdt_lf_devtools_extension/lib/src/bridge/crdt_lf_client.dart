// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:convert';
import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/crdt_lf_bridge.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/models/models.dart';

/// Typed calls to the `crdt_lf` DevTools protocol over a [bridge].
///
/// Every call throws a [BridgeCallException] when the app refuses it.
class CrdtLfClient {
  const CrdtLfClient(this.bridge);

  /// The protocol version this client speaks.
  static const int protocol = 1;

  final CrdtLfBridge bridge;

  /// The events of [bridge]; an unknown kind is skipped.
  Stream<CrdtLfEvent> get events =>
      bridge.events
          .map(CrdtLfEvent.fromBridge)
          .where((event) => event != null)
          .cast<CrdtLfEvent>();

  /// The live documents of the app.
  ///
  /// Throws a [BridgeCallException] when the app speaks another [protocol].
  Future<List<DocumentSummary>> documents() => _documents(const {});

  /// The summary of the live document [doc].
  ///
  /// Throws a [BridgeCallException] when the app speaks another [protocol].
  Future<DocumentSummary> summary(int doc) async =>
      (await _documents(_doc(doc))).single;

  Future<List<DocumentSummary>> _documents(Map<String, String> params) async {
    final json = await bridge.call('documents', params);
    final version = json.integer('protocol');
    if (version != protocol) {
      throw BridgeCallException(
        'documents',
        'The app speaks protocol $version, this extension speaks $protocol',
      );
    }
    return [
      for (final document in json.objects('documents'))
        DocumentSummary.fromJson(document),
    ];
  }

  Future<DocumentDetail> document(int doc) async =>
      DocumentDetail.fromJson(await bridge.call('document', _doc(doc)));

  Future<HandlerList> handlers(int doc) async =>
      HandlerList.fromJson(await bridge.call('handlers', _doc(doc)));

  /// The value of the open [handler]; `null` when it is still at
  /// [revision].
  ///
  /// This builds the handler cache in the app, as a read by the app does.
  /// The limits default to the ones of the app.
  Future<HandlerValue?> handlerValue(
    int doc,
    String handler, {
    int? revision,
    int? maxItems,
    int? maxString,
    int? maxDepth,
  }) async {
    final json = await bridge.call('handlerValue', {
      ..._doc(doc),
      'handler': handler,
      if (revision != null) 'revision': '$revision',
      ..._limits(maxItems, maxString, maxDepth),
    });
    return json['unchanged'] == true ? null : HandlerValue.fromJson(json);
  }

  /// The changes newer than [since], in replay order, at most [limit].
  ///
  /// [since] defaults to the empty vector: every change.
  Future<ChangesPage> changes(
    int doc, {
    VersionVector? since,
    int? limit,
  }) async => ChangesPage.fromJson(
    await bridge.call('changes', {
      ..._doc(doc),
      if (since != null) 'since': base64Encode(since.toBytes()),
      if (limit != null) 'limit': '$limit',
    }),
  );

  /// Decodes the operation of the [change] bytes with its open handler.
  Future<OperationInfo> operation(int doc, Uint8List change) async =>
      OperationInfo.fromJson(
        await bridge.call('operation', {
          ..._doc(doc),
          'change': base64Encode(change),
        }),
      );

  /// Opens a time travel session; it ends the previous one of [doc].
  Future<HistorySessionInfo> historyOpen(int doc) async =>
      HistorySessionInfo.fromJson(await bridge.call('historyOpen', _doc(doc)));

  /// Moves the [session] to [cursor] and reads [handler] there; no value
  /// when [handler] is `null`.
  Future<HistoryState> historyState(
    int doc, {
    required int session,
    required int cursor,
    String? handler,
    int? maxItems,
    int? maxString,
    int? maxDepth,
  }) async => HistoryState.fromJson(
    await bridge.call('historyState', {
      ..._doc(doc),
      'session': '$session',
      'cursor': '$cursor',
      if (handler != null) 'handler': handler,
      ..._limits(maxItems, maxString, maxDepth),
    }),
  );

  /// Ends [session]; a stale one is a no-op.
  Future<void> historyClose(int doc, int session) =>
      bridge.call('historyClose', {..._doc(doc), 'session': '$session'});

  Future<SnapshotInfo> snapshot(int doc) async =>
      SnapshotInfo.fromJson(await bridge.call('snapshot', _doc(doc)));

  /// Starts the event log of [doc] and returns `true`.
  ///
  /// The app then builds one event per move of the document.
  Future<bool> eventsStart(int doc) async =>
      (await bridge.call('eventsStart', _doc(doc))).boolean('recording');

  /// Stops the event log of [doc] and returns `false`.
  Future<bool> eventsStop(int doc) async =>
      (await bridge.call('eventsStop', _doc(doc))).boolean('recording');

  /// Watches the deltas of [handler] and returns `true`.
  ///
  /// A watched handler applies remote changes when they arrive, not at the
  /// next read.
  Future<bool> watchStart(int doc, String handler) async => (await bridge.call(
    'watchStart',
    {..._doc(doc), 'handler': handler},
  )).boolean('watching');

  /// Stops the delta watch of [handler] and returns `false`.
  Future<bool> watchStop(int doc, String handler) async => (await bridge.call(
    'watchStop',
    {..._doc(doc), 'handler': handler},
  )).boolean('watching');

  static Map<String, String> _doc(int doc) => {'doc': '$doc'};

  static Map<String, String> _limits(
    int? maxItems,
    int? maxString,
    int? maxDepth,
  ) => {
    if (maxItems != null) 'maxItems': '$maxItems',
    if (maxString != null) 'maxString': '$maxString',
    if (maxDepth != null) 'maxDepth': '$maxDepth',
  };
}
