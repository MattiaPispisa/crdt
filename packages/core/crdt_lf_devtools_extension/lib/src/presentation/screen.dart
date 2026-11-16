// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:crdt_lf_devtools_extension/src/application/connection/connection_cubit.dart';
import 'package:crdt_lf_devtools_extension/src/application/documents/documents_cubit.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/crdt_lf_bridge.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/crdt_lf_client.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/header/document_header.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/widgets/message.dart';
import 'package:devtools_app_shared/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The whole tool: the connection states, the document header and the
/// tabs.
///
/// It owns [bridge] and disposes it.
class CrdtLfScreen extends StatefulWidget {
  const CrdtLfScreen({required this.bridge, super.key});

  final CrdtLfBridge bridge;

  /// The text shown when DevTools is not connected to an app.
  static const String notConnected = 'Not connected to an app.';

  /// The text shown when the app has no `crdt_lf` document.
  static const String noDocument =
      'No crdt_lf document yet. The app registers this tool with its first '
      'CRDTDocument.';

  /// The text of the banner shown while the app is paused.
  static const String paused = 'The app is paused. Resume it to refresh.';

  @override
  State<CrdtLfScreen> createState() => _CrdtLfScreenState();
}

class _CrdtLfScreenState extends State<CrdtLfScreen> {
  late final ConnectionCubit _connection;

  late final DocumentsCubit _documents;

  @override
  void initState() {
    super.initState();
    _connection = ConnectionCubit(widget.bridge);
    _documents = DocumentsCubit(CrdtLfClient(widget.bridge));
  }

  @override
  void dispose() {
    unawaited(_documents.close());
    unawaited(_connection.close());
    widget.bridge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: _connection),
        BlocProvider.value(value: _documents),
      ],
      child: BlocBuilder<ConnectionCubit, ConnectionStatus>(
        builder:
            (context, connection) => Column(
              children: [
                if (connection.paused) const _PausedBanner(),
                Expanded(child: _body(connection)),
              ],
            ),
      ),
    );
  }

  Widget _body(ConnectionStatus connection) {
    if (!connection.connected) {
      return const PaneMessage(CrdtLfScreen.notConnected);
    }
    if (!connection.available) {
      return const PaneMessage(CrdtLfScreen.noDocument);
    }
    return BlocBuilder<DocumentsCubit, DocumentsState>(
      builder:
          (context, state) => switch (state.status) {
            DocumentsStatus.initial => const PaneMessage('Loading documents…'),
            DocumentsStatus.failure => PaneMessage(
              'The call failed: ${state.error}',
              onRetry: _documents.refresh,
            ),
            DocumentsStatus.loaded when state.documents.isEmpty =>
              const PaneMessage(CrdtLfScreen.noDocument),
            DocumentsStatus.loaded => _DocumentView(state: state),
          },
    );
  }
}

class _PausedBanner extends StatelessWidget {
  const _PausedBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.secondaryContainer,
      padding: const EdgeInsets.symmetric(
        horizontal: defaultSpacing,
        vertical: densePadding,
      ),
      child: Text(
        CrdtLfScreen.paused,
        style: theme.regularTextStyle.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

class _DocumentView extends StatelessWidget {
  const _DocumentView({required this.state});

  final DocumentsState state;

  static const List<(String, int)> _tabs = [
    ('State', 9),
    ('Changes', 10),
    ('Time travel', 12),
    ('Storage', 13),
    ('Events', 14),
  ];

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _tabs.length,
      child: Column(
        children: [
          DocumentHeader(state: state),
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [for (final (name, _) in _tabs) Tab(text: name)],
          ),
          Expanded(
            child: TabBarView(
              children: [
                for (final (_, step) in _tabs)
                  PaneMessage('Coming in step $step.'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
