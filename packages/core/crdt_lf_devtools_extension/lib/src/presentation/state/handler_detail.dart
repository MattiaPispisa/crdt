// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:convert';

import 'package:crdt_lf_devtools_extension/src/application/deltas/delta_watch_cubit.dart';
import 'package:crdt_lf_devtools_extension/src/application/handlers/handler_value_cubit.dart';
import 'package:crdt_lf_devtools_extension/src/application/handlers/handlers_cubit.dart';
import 'package:crdt_lf_devtools_extension/src/application/load_status.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/models/models.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/widgets/handler_names.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/widgets/message.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/widgets/text_copier.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/widgets/value_tree.dart';
import 'package:devtools_app_shared/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The fields and the value of the handler selected in [HandlersCubit].
class HandlerDetail extends StatelessWidget {
  const HandlerDetail({super.key});

  /// The note shown above the value.
  static const String cacheNote =
      'Reading a value builds the handler cache in the app, as a read by the '
      'app does.';

  /// The text shown when no handler is selected.
  static const String noSelection = 'Select a handler.';

  /// The note shown for a closed handler.
  static const String closedNote =
      'The handler is not open in the app: its value cannot be read.';

  /// The note under the Watch deltas toggle.
  static const String watchNote =
      'A watched handler applies remote changes when they arrive, not at the '
      'next read.';

  /// The note shown when the app stopped the watch for a while.
  static const String missedNote =
      'The app stopped the watch for a while: some deltas are missing.';

  /// The note shown for a deleted handler.
  static const String deletedNote = 'The handler was deleted.';

  @override
  Widget build(BuildContext context) {
    final state = context.watch<HandlersCubit>().state;
    final open = state.selectedOpen;
    final closed = state.selectedClosed;
    final id = state.selectedId;
    final names = HandlerNames.of(context);
    if (open != null) return _OpenDetail(open);
    if (closed != null) {
      return _Detail(
        title: HandlerNames.label(context, closed.id),
        fields: [
          ('id', closed.id),
          if (names[closed.id] case final name?) ('debugName', name),
          ('type', closed.type ?? 'unknown'),
          ('changeCount', '${closed.changeCount}'),
        ],
        children: const [_Note(closedNote)],
      );
    }
    if (id != null && state.selectedDeleted) {
      return _Detail(
        title: HandlerNames.label(context, id),
        fields: [
          ('id', id),
          if (names[id] case final name?) ('debugName', name),
        ],
        children: const [_Note(deletedNote)],
      );
    }
    return const PaneMessage(noSelection);
  }
}

class _OpenDetail extends StatelessWidget {
  const _OpenDetail(this.handler);

  final HandlerSummary handler;

  @override
  Widget build(BuildContext context) {
    final h = handler;
    final name = HandlerNames.of(context)[h.id];
    return _Detail(
      title: name ?? h.id,
      fields: [
        ('id', h.id),
        if (name != null) ('debugName', name),
        ('type', h.type),
        ('container', '${h.container}'),
        ('children', h.children.map((c) => c.id).join(', ')),
        ('changeCount', '${h.changeCount}'),
        ('revision', '${h.revision}'),
        ('cache', h.cache.name),
        ('pendingRemote', '${h.pendingRemote}'),
        ('deltas', '${h.deltas}'),
        ('watched', '${h.watched}'),
        ('deltaSeq', '${h.deltaSeq}'),
        ('invertible', '${h.invertible}'),
        ('undoTracked', '${h.undoTracked}'),
        ('snapshotBytes', '${h.snapshotBytes ?? '-'}'),
      ],
      children: [
        const _Note(HandlerDetail.cacheNote),
        const _ValuePane(),
        if (h.deltas) const _DeltaPane(),
      ],
    );
  }
}

class _ValuePane extends StatelessWidget {
  const _ValuePane();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<HandlerValueCubit>().state;
    final value = state.value;
    final copy = context.read<TextCopier>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AreaPaneHeader(
          title: Text(value == null ? 'Value' : 'Value · r${value.revision}'),
          roundedTopBorder: false,
          actions: [
            DevToolsButton.iconOnly(
              icon: Icons.copy,
              tooltip: 'Copy',
              onPressed:
                  value == null
                      ? null
                      : () => copy(
                        const JsonEncoder.withIndent('  ').convert(value.value),
                      ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.all(densePadding),
          child: switch (state.status) {
            LoadStatus.failure => PaneMessage(
              'The call failed: ${state.error}',
              onRetry: context.read<HandlerValueCubit>().refresh,
            ),
            _ when value == null => const PaneMessage('Loading the value…'),
            _ => ValueTree(
              value.value,
              onRef: context.read<HandlersCubit>().select,
            ),
          },
        ),
      ],
    );
  }
}

class _DeltaPane extends StatelessWidget {
  const _DeltaPane();

  static const double _listHeight = 12 * defaultRowHeight;

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<DeltaWatchCubit>();
    final state = cubit.state;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AreaPaneHeader(
          title: const Text('Deltas'),
          roundedTopBorder: false,
          actions: [
            DevToolsToggleButton(
              icon: Icons.visibility,
              label: 'Watch deltas',
              message: 'Watch the deltas of this handler',
              isSelected: state.watching,
              onPressed: () => cubit.setWatching(watching: !state.watching),
            ),
          ],
        ),
        const _Note(HandlerDetail.watchNote),
        if (state.missed) const _Note(HandlerDetail.missedNote),
        if (state.error case final error?)
          PaneMessage(
            'The call failed: $error',
            onRetry: () => cubit.setWatching(watching: !state.watching),
          ),
        if (state.deltas.isNotEmpty)
          SizedBox(
            height: _listHeight,
            child: ListView.builder(
              itemCount: state.deltas.length,
              itemExtent: defaultRowHeight,
              itemBuilder: (context, i) {
                final d = state.deltas[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: densePadding),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 50,
                        child: Text('${d.seq}', style: theme.fixedFontStyle),
                      ),
                      SizedBox(
                        width: 60,
                        child: Text(d.type, style: theme.regularTextStyle),
                      ),
                      Expanded(
                        child: Text(
                          (d.type == 'reset' ? d.cause : d.delta) ?? '',
                          style: theme.fixedFontStyle,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(
                        width: 60,
                        child: Text(switch (d.local) {
                          true => 'local',
                          false => 'remote',
                          null => '',
                        }, style: theme.subtleTextStyle),
                      ),
                      SizedBox(
                        width: 120,
                        child: Text(
                          d.origin ?? '',
                          style: theme.subtleTextStyle,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({
    required this.title,
    required this.fields,
    required this.children,
  });

  final String title;

  final List<(String, String)> fields;

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SelectionArea(
      child: ListView(
        children: [
          AreaPaneHeader(
            title: Text(title, style: theme.fixedFontStyle),
            roundedTopBorder: false,
            includeTopBorder: false,
          ),
          Padding(
            padding: const EdgeInsets.all(densePadding),
            child: Table(
              columnWidths: const {0: IntrinsicColumnWidth()},
              children: [
                for (final (label, value) in fields)
                  TableRow(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: defaultSpacing),
                        child: Text(label, style: theme.subtleTextStyle),
                      ),
                      Text(value, style: theme.fixedFontStyle),
                    ],
                  ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(densePadding),
    child: Text(text, style: Theme.of(context).subtleTextStyle),
  );
}
