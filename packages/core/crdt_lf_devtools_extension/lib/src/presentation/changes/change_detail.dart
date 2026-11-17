// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:convert';
import 'dart:typed_data';

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_devtools_extension/src/application/changes/change_log_cubit.dart';
import 'package:crdt_lf_devtools_extension/src/application/load_status.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/changes/change_row.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/widgets/message.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/widgets/peer_chip.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/widgets/text_copier.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/widgets/value_tree.dart';
import 'package:devtools_app_shared/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The fields, the operation and the bytes of the change selected in
/// [ChangeLogCubit].
class ChangeDetail extends StatelessWidget {
  const ChangeDetail({required this.localPeer, super.key});

  /// The peer id of the document.
  final String localPeer;

  /// The text shown when no change is selected.
  static const String noSelection = 'Select a change.';

  /// The note shown when the app cannot decode the operation.
  static const String closedNote =
      'The handler is not open in the app: the operation cannot be decoded.';

  /// The label of a change that no loaded change depends on.
  static const String frontierLabel = 'frontier';

  /// How many bytes [hex] shows.
  static const int hexBytes = 256;

  /// The first [hexBytes] of [bytes] in hex, then `…` when there are
  /// more.
  static String hex(Uint8List bytes) {
    final shown = bytes.length > hexBytes ? bytes.sublist(0, hexBytes) : bytes;
    final text = [
      for (final b in shown) b.toRadixString(16).padLeft(2, '0'),
    ].join(' ');
    return bytes.length > hexBytes ? '$text …' : text;
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ChangeLogCubit>().state;
    final entry = state.selected;
    if (entry == null) return const PaneMessage(noSelection);
    final theme = Theme.of(context);
    final change = entry.change;
    final hlc = change.hlc;
    final author = change.author.toString();
    final date = DateTime.fromMillisecondsSinceEpoch(hlc.l);
    final dependents = state.index.dependentsOf(change.id);
    final deps = entry.deps.toList()..sort();
    final copy = context.read<TextCopier>();
    return SelectionArea(
      child: ListView(
        children: [
          AreaPaneHeader(
            title: Text('${change.id}', style: theme.fixedFontStyle),
            roundedTopBorder: false,
            includeTopBorder: false,
            actions: [
              if (dependents.isEmpty)
                const RoundedLabel(labelText: frontierLabel),
            ],
          ),
          _Fields([
            ('id', Text('${change.id}', style: theme.fixedFontStyle)),
            (
              'clock',
              Text(
                '${hlc.l}.${hlc.c} · ${date.toIso8601String()}',
                style: theme.fixedFontStyle,
              ),
            ),
            (
              'author',
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: densePadding,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    PeerChip(author, local: author == localPeer),
                    Text(author, style: theme.fixedFontStyle),
                  ],
                ),
              ),
            ),
            ('dependencies', _Links(deps, state)),
            ('dependents', _Links(dependents, state)),
            (
              'handler',
              Text(entry.handlerId ?? '?', style: theme.fixedFontStyle),
            ),
            (
              'handlerType',
              Text(entry.handlerType ?? '?', style: theme.fixedFontStyle),
            ),
            (
              'kind',
              Text(
                '${kindLabel(entry.kind)} (${entry.kind ?? '?'})',
                style: theme.fixedFontStyle,
              ),
            ),
            (
              'stamped',
              Text('${entry.stamped ?? '?'}', style: theme.fixedFontStyle),
            ),
            (
              'size',
              Text('${entry.byteLength} B', style: theme.fixedFontStyle),
            ),
          ]),
          const AreaPaneHeader(
            title: Text('Operation'),
            roundedTopBorder: false,
          ),
          Padding(
            padding: const EdgeInsets.all(densePadding),
            child: _operation(context, state),
          ),
          AreaPaneHeader(
            title: Text('Bytes · ${entry.byteLength}'),
            roundedTopBorder: false,
            actions: [
              DevToolsButton(
                icon: Icons.copy,
                label: 'Copy base64',
                onPressed: () => copy(base64Encode(entry.bytes)),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.all(densePadding),
            child: Text(hex(entry.bytes), style: theme.fixedFontStyle),
          ),
        ],
      ),
    );
  }

  Widget _operation(BuildContext context, ChangeLogState state) {
    final operation = state.operation;
    final subtle = Theme.of(context).subtleTextStyle;
    return switch (state.operationStatus) {
      LoadStatus.initial => const PaneMessage('Loading the operation…'),
      LoadStatus.failure => PaneMessage(
        'The call failed: ${state.operationError}',
        onRetry: context.read<ChangeLogCubit>().reloadOperation,
      ),
      LoadStatus.loaded when operation == null => const SizedBox.shrink(),
      LoadStatus.loaded when operation!.error != null => Text(
        'The operation cannot be decoded: ${operation.error}',
        style: subtle,
      ),
      LoadStatus.loaded when !operation!.open => Text(
        closedNote,
        style: subtle,
      ),
      LoadStatus.loaded => ValueTree(operation!.payload),
    };
  }
}

class _Fields extends StatelessWidget {
  const _Fields(this.fields);

  final List<(String, Widget)> fields;

  @override
  Widget build(BuildContext context) {
    final subtle = Theme.of(context).subtleTextStyle;
    return Padding(
      padding: const EdgeInsets.all(densePadding),
      child: Table(
        columnWidths: const {0: IntrinsicColumnWidth()},
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          for (final (label, value) in fields)
            TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: defaultSpacing),
                  child: Text(label, style: subtle),
                ),
                value,
              ],
            ),
        ],
      ),
    );
  }
}

class _Links extends StatelessWidget {
  const _Links(this.ids, this.state);

  final List<OperationId> ids;

  final ChangeLogState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (ids.isEmpty) return Text('none', style: theme.subtleTextStyle);
    final cubit = context.read<ChangeLogCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final id in ids)
          if (state.index.byId.containsKey(id))
            InkWell(
              onTap: () => cubit.select(id),
              child: Text(
                '→ $id',
                style: theme.fixedFontStyle.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            )
          else
            Text('$id (not loaded)', style: theme.subtleTextStyle),
      ],
    );
  }
}
