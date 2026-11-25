// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_devtools_extension/src/application/connection/connection_cubit.dart';
import 'package:crdt_lf_devtools_extension/src/application/documents/documents_cubit.dart';
import 'package:crdt_lf_devtools_extension/src/application/events/event_log_cubit.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/change_mirror.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/crdt_lf_bridge.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/crdt_lf_client.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/changes/changes_tab.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/events/events_tab.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/header/document_header.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/state/state_tab.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/storage/storage_tab.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/time_travel/time_travel_tab.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/widgets/change_link.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/widgets/handler_names.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/widgets/message.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/widgets/text_copier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The whole tool: the connection states, the document header and the
/// tabs.
///
/// It owns [bridge] and disposes it.
class CrdtLfScreen extends StatefulWidget {
  const CrdtLfScreen({
    required this.bridge,
    this.copier = TextCopier.clipboard,
    super.key,
  });

  final CrdtLfBridge bridge;

  /// Copies the texts the user asks for.
  final TextCopier copier;

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
  late final CrdtLfClient _client;

  late final ConnectionCubit _connection;

  late final DocumentsCubit _documents;

  @override
  void initState() {
    super.initState();
    _client = CrdtLfClient(widget.bridge);
    _connection = ConnectionCubit(widget.bridge);
    _documents = DocumentsCubit(_client);
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
        RepositoryProvider.value(value: _client),
        RepositoryProvider.value(value: widget.copier),
        BlocProvider.value(value: _connection),
        BlocProvider.value(value: _documents),
      ],
      child: BlocBuilder<ConnectionCubit, ConnectionStatus>(
        builder:
            (context, connection) => Column(
              children: [
                if (connection.paused) const MessageBanner(CrdtLfScreen.paused),
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
            DocumentsStatus.failure when state.documents.isEmpty => PaneMessage(
              'The call failed: ${state.error}',
              onRetry: _documents.refresh,
            ),
            DocumentsStatus.loaded when state.documents.isEmpty =>
              const PaneMessage(CrdtLfScreen.noDocument),
            // A failed reload keeps the tabs: closing them would end the
            // event log, the watch and the time travel session.
            _ => _DocumentView(state: state),
          },
    );
  }
}

class _DocumentView extends StatelessWidget {
  const _DocumentView({required this.state});

  final DocumentsState state;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
      child: Column(
        children: [
          DocumentHeader(state: state),
          if (state.error case final error?)
            MessageBanner(
              'The call failed: $error',
              onRetry: context.read<DocumentsCubit>().refresh,
            ),
          Expanded(
            child: HandlerNames(
              names: state.selected?.handlerNames ?? const {},
              child: _DocumentTabs(
                key: ValueKey(state.selectedId),
                doc: state.selectedId!,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The tabs of one document. The event log and the change mirror live here:
/// the log keeps recording, and the mirror keeps the loaded changes, while
/// another tab is shown.
class _DocumentTabs extends StatefulWidget {
  const _DocumentTabs({required this.doc, super.key});

  final int doc;

  @override
  State<_DocumentTabs> createState() => _DocumentTabsState();
}

class _DocumentTabsState extends State<_DocumentTabs> {
  static const int _changesTab = 1;

  late final EventLogCubit _events;

  late final ChangeMirror _mirror;

  final ChangeLink _link = ChangeLink();

  @override
  void initState() {
    super.initState();
    final client = context.read<CrdtLfClient>();
    _events = EventLogCubit(client, widget.doc);
    _mirror = ChangeMirror(client, widget.doc);
  }

  @override
  void dispose() {
    unawaited(_events.close());
    _link.dispose();
    super.dispose();
  }

  void _openChange(OperationId id) {
    _link.open(id);
    DefaultTabController.of(context).animateTo(_changesTab);
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _events,
      child: Column(
        children: [
          const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'State'),
              Tab(text: 'Changes'),
              Tab(text: 'Time travel'),
              Tab(text: 'Storage'),
              Tab(text: 'Events'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                StateTab(doc: widget.doc),
                ChangesTab(mirror: _mirror, link: _link),
                TimeTravelTab(mirror: _mirror),
                StorageTab(doc: widget.doc),
                EventsTab(onChange: _openChange),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
