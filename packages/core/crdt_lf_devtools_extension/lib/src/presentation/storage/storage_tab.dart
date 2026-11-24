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
      // Slivers: a snapshot can hold thousands of entries, and the page is
      // built again on each change of the document.
      child: CustomScrollView(
        slivers: [
          _box(const _Section('Version')),
          _box(FieldTable.texts([('frontiers', summary.frontiers.join(', '))])),
          _VersionVector(summary.versionVector, local: summary.peerId),
          _box(const _Section('Snapshot')),
          if (snapshot == null)
            _box(_Line(StorageTab.noSnapshot, style: theme.subtleTextStyle))
          else ...[
            _box(
              FieldTable([
                ('id', _SnapshotId(snapshot.id)),
                ('bytes', _mono(context, '${snapshot.bytes}')),
              ]),
            ),
            _VersionVector(snapshot.versionVector, local: summary.peerId),
            _Entries(state.entriesBySize),
          ],
          if (unfolded.isNotEmpty) ...[
            _box(const _Section('Carried changes')),
            _Unfolded(unfolded),
          ],
          if (info.deleted.isNotEmpty) ...[
            _box(const _Section('Deleted handlers')),
            _SliverTable(
              widths: const [null],
              count: info.deleted.length,
              row: (i) => [_handler(context, info.deleted[i])],
            ),
          ],
          _box(const _Section('Formats')),
          _box(_Formats(state.formats)),
          _box(const _Section('Undo managers')),
          if (detail.undo.isEmpty)
            _box(_Line('None.', style: theme.subtleTextStyle))
          else
            for (final (i, m) in detail.undo.indexed)
              _box(
                _Line(
                  '#$i · undo ${m.undoDepth} · redo ${m.redoDepth} · '
                  'tracked [${m.tracked.map(label).join(', ')}] · '
                  'limit ${m.stackLimit} · '
                  'capture ${m.captureTimeout.inMilliseconds} ms',
                  style: theme.fixedFontStyle,
                ),
              ),
          _box(const SizedBox(height: defaultSpacing)),
        ],
      ),
    );
  }
}

Widget _box(Widget child) => SliverToBoxAdapter(child: child);

// One line, with the whole text (or [tooltip]) on hover.
Widget _mono(BuildContext context, String text, {String? tooltip}) =>
    DevToolsTooltip(
      message: tooltip ?? text,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).fixedFontStyle,
      ),
    );

// A handler by its debug name, with its id on hover.
Widget _handler(BuildContext context, String id) =>
    _mono(context, HandlerNames.label(context, id), tooltip: id);

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

/// A lazy table: one row of [defaultRowHeight] per index of [row], under
/// [header] when it has one.
class _SliverTable extends StatelessWidget {
  const _SliverTable({
    required this.widths,
    required this.count,
    required this.row,
    this.header,
  });

  final List<String>? header;

  /// The width of each column; `null` shares what is left.
  final List<double?> widths;

  /// The width of a column of numbers.
  static const double number = 120;

  final int count;

  final List<Widget> Function(int index) row;

  @override
  Widget build(BuildContext context) {
    final subtle = Theme.of(context).subtleTextStyle;
    final offset = header == null ? 0 : 1;
    return SliverPadding(
      padding: const EdgeInsets.all(densePadding),
      sliver: SliverFixedExtentList.builder(
        itemExtent: defaultRowHeight,
        itemCount: count + offset,
        itemBuilder: (context, i) {
          final cells =
              i < offset
                  ? [for (final title in header!) Text(title, style: subtle)]
                  : row(i - offset);
          return Row(
            children: [
              for (final (column, cell) in cells.indexed)
                if (widths[column] case final width?)
                  SizedBox(width: width, child: _cell(cell))
                else
                  Expanded(child: _cell(cell)),
            ],
          );
        },
      ),
    );
  }

  // A label keeps its own width.
  static Widget _cell(Widget child) => Padding(
    padding: const EdgeInsets.only(right: defaultSpacing),
    child: Align(alignment: Alignment.centerLeft, child: child),
  );
}

class _VersionVector extends StatelessWidget {
  const _VersionVector(this.vector, {required this.local});

  final Map<String, String> vector;

  final String local;

  @override
  Widget build(BuildContext context) {
    final entries = vector.entries.toList();
    return _SliverTable(
      header: const ['peer', 'clock'],
      widths: const [null, null],
      count: entries.length,
      row: (i) {
        final MapEntry(:key, :value) = entries[i];
        return [PeerChip(key, local: key == local), _mono(context, value)];
      },
    );
  }
}

class _Entries extends StatelessWidget {
  const _Entries(this.entries);

  final List<SnapshotEntry> entries;

  @override
  Widget build(BuildContext context) => _SliverTable(
    header: const ['key', 'type', 'bytes'],
    widths: const [null, null, _SliverTable.number],
    count: entries.length,
    row: (i) {
      final e = entries[i];
      return [
        if (e.reserved) _mono(context, e.key) else _handler(context, e.key),
        if (e.reserved)
          const RoundedLabel(labelText: 'reserved')
        else
          _mono(context, e.type ?? '-'),
        _mono(context, '${e.bytes}'),
      ];
    },
  );
}

class _Unfolded extends StatelessWidget {
  const _Unfolded(this.counts);

  final Map<String, int?> counts;

  @override
  Widget build(BuildContext context) {
    final entries = counts.entries.toList();
    return _SliverTable(
      header: const ['handler', 'changes'],
      widths: const [null, _SliverTable.number],
      count: entries.length,
      row: (i) {
        final MapEntry(:key, :value) = entries[i];
        return [
          _handler(context, key),
          // `null` when the app cannot read the record.
          _mono(context, '${value ?? '?'}'),
        ];
      },
    );
  }
}

class _Formats extends StatelessWidget {
  const _Formats(this.formats);

  final List<FormatRow> formats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Table(
      header: const ['type', 'this build reads', 'the data needs'],
      rows: [
        for (final row in formats)
          [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: Text(row.type, style: theme.fixedFontStyle)),
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
            Text(row.reads ?? '-', style: theme.fixedFontStyle),
            Text(row.needs ?? '-', style: theme.fixedFontStyle),
          ],
      ],
    );
  }
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
