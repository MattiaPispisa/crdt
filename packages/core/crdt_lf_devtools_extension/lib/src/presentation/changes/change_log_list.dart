// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf_devtools_extension/src/application/changes/change_log_cubit.dart';
import 'package:crdt_lf_devtools_extension/src/application/changes/row_graph.dart';
import 'package:crdt_lf_devtools_extension/src/application/load_status.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/changes/change_row.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/changes/lane_graph_painter.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/widgets/handler_names.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/widgets/keyboard_list.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/widgets/message.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/widgets/peer_color.dart';
import 'package:devtools_app_shared/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The filters and the changes of [ChangeLogCubit].
class ChangeLogList extends StatefulWidget {
  const ChangeLogList({
    required this.localPeer,
    required this.hasSnapshot,
    super.key,
  });

  /// The peer id of the document.
  final String localPeer;

  /// Adds the [snapshotRow] at the oldest end of the list.
  final bool hasSnapshot;

  /// The row that stands for the changes the snapshot holds.
  static const String snapshotRow = 'Older changes are in the snapshot';

  @override
  State<ChangeLogList> createState() => _ChangeLogListState();
}

class _ChangeLogListState extends State<ChangeLogList> {
  final TextEditingController _text = TextEditingController();

  @override
  void initState() {
    super.initState();
    _text.addListener(() {
      final cubit = context.read<ChangeLogCubit>();
      cubit.setFilter(cubit.state.filter.copyWith(text: _text.text));
    });
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(densePadding),
          child: DevToolsClearableTextField(
            controller: _text,
            hintText: 'Filter by change id',
          ),
        ),
        const _Filters(),
        Expanded(
          child: BlocBuilder<ChangeLogCubit, ChangeLogState>(builder: _list),
        ),
      ],
    );
  }

  Widget _list(BuildContext context, ChangeLogState state) {
    if (state.status == LoadStatus.initial) {
      return PaneMessage.loadingChanges(state.progress);
    }
    if (state.status == LoadStatus.failure && state.index.entries.isEmpty) {
      return PaneMessage(
        'The call failed: ${state.error}',
        onRetry: context.read<ChangeLogCubit>().refresh,
      );
    }
    final rows = state.visible;
    final snapshot = widget.hasSnapshot;
    if (rows.isEmpty && !snapshot) {
      return PaneMessage(
        state.filter.isEmpty ? 'No changes yet.' : 'No change matches.',
      );
    }
    final count = rows.length + (snapshot ? 1 : 0);
    final snapshotAt = state.newestFirst ? count - 1 : 0;
    final offset = snapshot && !state.newestFirst ? 1 : 0;
    final graph = state.index.graph;
    // A filter hides rows, so the lines would join changes that are not
    // next to each other.
    final showGraph = state.filter.isEmpty && graph.laneCount > 0;
    final colors = [
      for (var lane = 0; lane < graph.laneCount; lane++)
        if (graph.sharedLastLane && lane == LaneGraph.maxLanes - 1)
          Theme.of(context).colorScheme.outline
        else
          peerColor(graph.peers[lane]),
    ];
    final last = rows.length - 1;
    final cubit = context.read<ChangeLogCubit>();
    return KeyboardList(
      itemCount: count,
      selectedIndex: () {
        final id = cubit.state.selectedId;
        final at = rows.indexWhere((e) => e.change.id == id);
        return at < 0 ? null : at + offset;
      },
      canSelect: (i) => !snapshot || i != snapshotAt,
      onSelect: (i) => cubit.select(rows[i - offset].change.id),
      itemBuilder: (context, i) {
        if (snapshot && i == snapshotAt) {
          return Center(
            child: Text(
              ChangeLogList.snapshotRow,
              style: Theme.of(context).subtleTextStyle,
            ),
          );
        }
        final at = i - offset;
        final entry = rows[at];
        final id = entry.change.id;
        return ChangeRow(
          graph:
              showGraph
                  ? CustomPaint(
                    size: Size(
                      graph.laneCount * LaneGraphPainter.laneWidth,
                      defaultRowHeight,
                    ),
                    painter: LaneGraphPainter(
                      row: graph.rows[state.newestFirst ? last - at : at],
                      colors: colors,
                      olderAbove: !state.newestFirst,
                    ),
                  )
                  : null,
          entry: entry,
          local: entry.change.author.toString() == widget.localPeer,
          selected: id == state.selectedId,
          onTap: () => context.read<ChangeLogCubit>().select(id),
        );
      },
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters();

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<ChangeLogCubit>();
    final state = cubit.state;
    final filter = state.filter;
    final index = state.index;
    final names = HandlerNames.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: densePadding),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _dropdown<String>(
                value: filter.author,
                all: 'All authors',
                values: index.authors,
                label: (a) => a.length > 8 ? a.substring(0, 8) : a,
                onChanged:
                    (v) => cubit.setFilter(filter.copyWith(author: () => v)),
              ),
              const SizedBox(width: densePadding),
              _dropdown<String>(
                value: filter.handler,
                all: 'All handlers',
                values: index.handlers,
                label: (h) => names[h] ?? h,
                onChanged:
                    (v) => cubit.setFilter(filter.copyWith(handler: () => v)),
              ),
              const SizedBox(width: densePadding),
              _dropdown<int>(
                value: filter.kind,
                all: 'All kinds',
                values: index.kinds,
                label: kindLabel,
                onChanged:
                    (v) => cubit.setFilter(filter.copyWith(kind: () => v)),
              ),
              const SizedBox(width: densePadding),
              DevToolsToggleButton(
                icon: Icons.swap_vert,
                label: 'Newest first',
                message: 'Show the newest change first',
                isSelected: state.newestFirst,
                onPressed:
                    () => cubit.setNewestFirst(newestFirst: !state.newestFirst),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dropdown<T extends Object>({
    required T? value,
    required String all,
    required List<T> values,
    required String Function(T) label,
    required ValueChanged<T?> onChanged,
  }) => RoundedDropDownButton<T>(
    value: values.contains(value) ? value : null,
    isDense: true,
    onChanged: onChanged,
    items: [
      DropdownMenuItem<T>(child: Text(all)),
      for (final v in values)
        DropdownMenuItem<T>(value: v, child: Text(label(v))),
    ],
  );
}
