// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_flutter/crdt_lf_flutter.dart';
import 'package:crdt_lf_flutter/src/provider/_crdt_view.dart';
import 'package:flutter/widgets.dart';

/// Convenience access to the ambient [CRDTDocument].
extension CrdtContextHelper on BuildContext {
  /// The [CRDTDocument] provided by the nearest [CrdtProvider] (one-off read).
  CRDTDocument get crdtDocument => CrdtProvider.of(this);

  /// The [CRDTDocument] provided by the nearest [CrdtProvider].
  ///
  /// Rebuild the calling widget on every document update.
  CRDTDocument watchCrdtDocument() => CrdtProvider.of(this, listen: true);

  /// Rebuilds the calling widget only when the value derived by [selector] from
  /// the ambient [CRDTDocument] changes (provider's `context.select`).
  R selectCrdtDocument<R>(R Function(CRDTDocument document) selector) =>
      select<CRDTDocument, R>(selector);

  /// Resolves the handler registered under [id] on the nearest view, for
  /// **imperative** use (actions like insert/delete/change) — it does not
  /// rebuild the caller.
  ///
  /// Under a `CrdtHistoryScope` the view is the frozen document, so a write
  /// through the returned handler throws a [ReadOnlyDocumentException].
  ///
  /// Throws a [HandlerDeletedException] if the handler was deleted, and a
  /// [FlutterError] if no handler is registered for [id] or it is not an [H].
  H crdtHandler<H extends Handler<dynamic>>(String id) =>
      resolveCrdtHandler<H>(crdtView, id);
}

/// Returns the handler registered under [id] on [document], cast to [H].
///
/// Throws a [HandlerDeletedException] if the handler was deleted. Throws a
/// [FlutterError] if it is missing or has a different type — surfacing a
/// wiring mistake instead of a late `null`/cast error.
H resolveCrdtHandler<H extends Handler<dynamic>>(
  BaseCRDTDocument document,
  String id,
) {
  final handler = document.handlerById(id);
  if (handler == null && document.isDeleted(id)) {
    throw HandlerDeletedException(id);
  }
  if (handler == null) {
    throw FlutterError(
      'No CRDT handler is registered for id "$id".\n'
      'Create the handler on the document before reading it.',
    );
  }
  if (handler is! H) {
    throw FlutterError(
      'CRDT handler "$id" is a ${handler.runtimeType}, not the expected $H.',
    );
  }
  return handler;
}
