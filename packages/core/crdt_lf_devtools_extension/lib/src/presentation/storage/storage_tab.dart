// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:crdt_lf_devtools_extension/src/application/load_status.dart';
import 'package:crdt_lf_devtools_extension/src/application/storage/storage_cubit.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/crdt_lf_client.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/models/models.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/widgets/field_table.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/widgets/handler_names.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/widgets/message.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/widgets/peer_chip.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/widgets/text_copier.dart';
import 'package:devtools_app_shared/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// One scrolling page with the version, the snapshot, the carried changes,
/// the deleted handlers, the formats and the undo managers of [doc].
class StorageTab extends StatefulWidget {
  const StorageTab({required this.doc, super.key});

  /// The tracked id of the document.
  final int doc;

  /// The text shown before the first snapshot.
  static const String noSnapshot = 'No snapshot yet.';

  /// The label of a type the data needs and this build does not list.
  static const String missingLabel = 'not read by this build';

  @override
  State<StorageTab> createState() => _StorageTabState();
}

class _StorageTabState extends State<StorageTab> {
  late final StorageCubit _cubit;

  @override
  void initState() {
    super.initState();
    _cubit = StorageCubit(context.read<CrdtLfClient>(), widget.doc);
  }

  @override
  void dispose() {
    unawaited(_cubit.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<StorageCubit, StorageState>(
      bloc: _cubit,
      builder: (context, state) {
        final detail = state.detail;
        final info = state.snapshot;
        if (state.status == LoadStatus.failure && detail == null) {
          return PaneMessage(
            'The call failed: ${state.error}',
            onRetry: _cubit.refresh,
          );
        }
        if (detail == null || info == null) {
          return const PaneMessage('Loading the storage…');
        }
        return _StoragePage(state: state, detail: detail, info: info);
      },
    );
  }
}

class _StoragePage extends StatelessWidget {
  const _StoragePage({
    required this.state,
    required this.detail,
    required this.info,
  });

  final StorageState state;

  final DocumentDetail detail;

  final SnapshotInfo info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summary = detail.summary;
    final snapshot = info.snapshot;
    final unfolded = snapshot?.unfolded ?? const {};
    String label(String id) => HandlerNames.label(context, id);
    return SelectionArea(
      child: ListView(
        children: [
          const _Section('Version'),
          FieldTable([
            ('frontiers', _mono(context, summary.frontiers.join(', '))),
          ]),
          _VersionVector(summary.versionVector, local: summary.peerId),
          const _Section('Snapshot'),
          if (snapshot == null)
            _Line(StorageTab.noSnapshot, style: theme.subtleTextStyle)
          else ...[
            FieldTable([
              ('id', _SnapshotId(snapshot.id)),
              ('bytes', _mono(context, '${snapshot.bytes}')),
            ]),
            _VersionVector(snapshot.versionVector, local: summary.peerId),
            _Entries(state.entriesBySize),
          ],
          if (unfolded.isNotEmpty) ...[
            const _Section('Carried changes'),
            _Table(
              header: const ['handler', 'changes'],
              rows: [
                // A count is `null` when the app cannot read its record.
                for (final MapEntry(:key, :value) in unfolded.entries)
                  [
                    _mono(context, label(key)),
                    _mono(context, '${value ?? '?'}'),
                  ],
              ],
            ),
          ],
          if (info.deleted.isNotEmpty) ...[
            const _Section('Deleted handlers'),
            for (final id in info.deleted)
              _Line(label(id), style: theme.fixedFontStyle),
          ],
          const _Section('Formats'),
          _Table(
            header: const ['type', 'this build reads', 'the data needs'],
            rows: [
              for (final row in state.formats)
                [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(child: _mono(context, row.type)),
                      if (row.missing) ...[
                        const SizedBox(width: densePadding),
                        Icon(
                          Icons.warning_amber,
                          size: defaultIconSize,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(width: densePadding),
                        const RoundedLabel(labelText: StorageTab.missingLabel),
                      ],
                    ],
                  ),
                  _mono(context, row.reads ?? '-'),
                  _mono(context, row.needs ?? '-'),
                ],
            ],
          ),
          const _Section('Undo managers'),
          if (detail.undo.isEmpty)
            _Line('None.', style: theme.subtleTextStyle)
          else
            for (final (i, m) in detail.undo.indexed)
              _Line(
                '#$i · undo ${m.undoDepth} · redo ${m.redoDepth} · '
                'tracked [${m.tracked.map(label).join(', ')}] · '
                'limit ${m.stackLimit} · '
                'capture ${m.captureTimeout.inMilliseconds} ms',
                style: theme.fixedFontStyle,
              ),
          const SizedBox(height: defaultSpacing),
        ],
      ),
    );
  }
}

Widget _mono(BuildContext context, String text) =>
    Text(text, style: Theme.of(context).fixedFontStyle);

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) =>
      AreaPaneHeader(title: Text(title), roundedTopBorder: false);
}

class _Line extends StatelessWidget {
  const _Line(this.text, {required this.style});

  final String text;

  final TextStyle style;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(densePadding),
    child: Text(text, style: style),
  );
}

class _Table extends StatelessWidget {
  const _Table({required this.header, required this.rows});

  final List<String> header;

  final List<List<Widget>> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(densePadding),
      child: Table(
        defaultColumnWidth: const IntrinsicColumnWidth(),
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
            children: [
              for (final title in header)
                _cell(Text(title, style: theme.subtleTextStyle)),
            ],
          ),
          for (final row in rows)
            TableRow(children: [for (final c in row) _cell(c)]),
        ],
      ),
    );
  }

  static Widget _cell(Widget child) => Padding(
    padding: const EdgeInsets.only(right: defaultSpacing, bottom: densePadding),
    // A table cell is as wide as its column: a label keeps its own width.
    child: Align(alignment: Alignment.centerLeft, child: child),
  );
}

class _VersionVector extends StatelessWidget {
  const _VersionVector(this.vector, {required this.local});

  final Map<String, String> vector;

  final String local;

  @override
  Widget build(BuildContext context) => _Table(
    header: const ['peer', 'clock'],
    rows: [
      for (final MapEntry(:key, :value) in vector.entries)
        [PeerChip(key, local: key == local), _mono(context, value)],
    ],
  );
}

class _Entries extends StatelessWidget {
  const _Entries(this.entries);

  final List<SnapshotEntry> entries;

  @override
  Widget build(BuildContext context) => _Table(
    header: const ['key', 'type', 'bytes', ''],
    rows: [
      for (final e in entries)
        [
          _mono(
            context,
            e.reserved ? e.key : HandlerNames.label(context, e.key),
          ),
          _mono(context, e.type ?? '-'),
          _mono(context, '${e.bytes}'),
          if (e.reserved)
            const RoundedLabel(labelText: 'reserved')
          else
            const SizedBox(),
        ],
    ],
  );
}

class _SnapshotId extends StatelessWidget {
  const _SnapshotId(this.id);

  final String id;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Flexible(child: _mono(context, id)),
      DevToolsButton.iconOnly(
        icon: Icons.copy,
        tooltip: 'Copy the snapshot id',
        onPressed: () => context.read<TextCopier>()(id),
      ),
    ],
  );
}
