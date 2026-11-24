// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:crdt_lf_devtools_extension/src/application/documents/documents_cubit.dart';
import 'package:crdt_lf_devtools_extension/src/application/load_status.dart';
import 'package:crdt_lf_devtools_extension/src/application/time_travel/time_travel_cubit.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/change_mirror.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/changes/change_row.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/widgets/handler_icon.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/widgets/handler_names.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/widgets/keyboard_list.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/widgets/message.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/widgets/value_tree.dart';
import 'package:devtools_app_shared/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// A time travel session over the document of [mirror]: a cursor over its
/// changes, and the value of the selected handler at the cursor.
///
/// The session is open while the tab is shown.
class TimeTravelTab extends StatefulWidget {
  const TimeTravelTab({required this.mirror, super.key});

  final ChangeMirror mirror;

  /// The text shown at cursor 0.
  static const String start = 'No change applied.';

  /// The text shown when the changes of the session could not be loaded.
  static const String noCard = 'The change at the cursor is not loaded.';

  /// The text shown when no handler is selected.
  static const String noSelection = 'Select a handler.';

  @override
  State<TimeTravelTab> createState() => _TimeTravelTabState();
}

class _TimeTravelTabState extends State<TimeTravelTab> {
  late final TimeTravelCubit _travel;

  @override
  void initState() {
    super.initState();
    _travel = TimeTravelCubit(widget.mirror);
  }

  @override
  void dispose() {
    unawaited(_travel.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _travel,
      child: BlocBuilder<TimeTravelCubit, TimeTravelState>(
        builder: (context, state) {
          if (state.session == null) {
            return state.status == LoadStatus.failure
                ? PaneMessage(
                  'The call failed: ${state.error}',
                  onRetry: _travel.reopen,
                )
                : PaneMessage.loadingChanges(state.progress);
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _CursorBar(state),
              _CurrentChange(state),
              const Divider(height: 1),
              Expanded(
                child: SplitPane(
                  axis: Axis.horizontal,
                  initialFractions: const [0.4, 0.6],
                  children: [_HandlerList(state), _ValuePane(state)],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _CursorBar extends StatelessWidget {
  const _CursorBar(this.state);

  final TimeTravelState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final travel = context.read<TimeTravelCubit>();
    final length = state.length;
    return Padding(
      padding: const EdgeInsets.all(densePadding),
      child: Row(
        children: [
          DevToolsButton.iconOnly(
            icon: Icons.chevron_left,
            tooltip: 'Previous change',
            onPressed: state.cursor > 0 ? travel.previous : null,
          ),
          const SizedBox(width: densePadding),
          DevToolsButton.iconOnly(
            icon: Icons.chevron_right,
            tooltip: 'Next change',
            onPressed: state.cursor < length ? travel.next : null,
          ),
          Expanded(
            child: Slider(
              value: state.cursor.toDouble(),
              max: length.toDouble(),
              divisions: length > 0 ? length : null,
              onChanged:
                  length > 0 ? (value) => travel.moveTo(value.round()) : null,
            ),
          ),
          Text('${state.cursor} / $length', style: theme.fixedFontStyle),
          if (state.newChanges > 0) ...[
            const SizedBox(width: defaultSpacing),
            Text(
              '${state.newChanges} new changes',
              style: theme.subtleTextStyle,
            ),
            const SizedBox(width: densePadding),
            DevToolsButton(
              icon: Icons.refresh,
              label: 'Reopen',
              onPressed: travel.reopen,
            ),
          ],
        ],
      ),
    );
  }
}

class _CurrentChange extends StatelessWidget {
  const _CurrentChange(this.state);

  final TimeTravelState state;

  @override
  Widget build(BuildContext context) {
    final entry = state.current;
    final localPeer = context.select(
      (DocumentsCubit c) => c.state.selected?.peerId,
    );
    return SizedBox(
      height: defaultRowHeight,
      child:
          entry != null
              ? ChangeRow(
                entry: entry,
                local: entry.change.author.toString() == localPeer,
                selected: false,
                onTap: () {},
              )
              : Padding(
                padding: const EdgeInsets.symmetric(horizontal: densePadding),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    state.cursor == 0
                        ? TimeTravelTab.start
                        : TimeTravelTab.noCard,
                    style: Theme.of(context).subtleTextStyle,
                  ),
                ),
              ),
    );
  }
}

class _HandlerList extends StatelessWidget {
  const _HandlerList(this.state);

  final TimeTravelState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final handlers = state.session!.handlers;
    if (handlers.isEmpty) return const PaneMessage('No handler.');
    final travel = context.read<TimeTravelCubit>();
    return KeyboardList(
      itemCount: handlers.length,
      selectedIndex: () {
        final id = travel.state.handler;
        final i = handlers.indexWhere((h) => h.id == id);
        return i < 0 ? null : i;
      },
      onSelect: (i) => travel.select(handlers[i].id),
      itemBuilder: (context, i) {
        final handler = handlers[i];
        final selected = handler.id == state.handler;
        return Material(
          color:
              selected
                  ? theme.colorScheme.primary.withValues(alpha: 0.2)
                  : Colors.transparent,
          child: InkWell(
            onTap: () => context.read<TimeTravelCubit>().select(handler.id),
            child: Row(
              children: [
                const SizedBox(width: densePadding),
                Icon(handlerIcon(handler.type), size: defaultIconSize),
                const SizedBox(width: densePadding),
                Flexible(
                  child: Text(
                    HandlerNames.label(context, handler.id),
                    style: theme.fixedFontStyle,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: densePadding),
                Expanded(
                  child: Text(
                    handler.type,
                    style: theme.subtleTextStyle,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ValuePane extends StatelessWidget {
  const _ValuePane(this.state);

  final TimeTravelState state;

  @override
  Widget build(BuildContext context) {
    final handler = state.handler;
    if (handler == null) return const PaneMessage(TimeTravelTab.noSelection);
    final value = state.value;
    final theme = Theme.of(context);
    return SelectionArea(
      child: ListView(
        children: [
          AreaPaneHeader(
            title: Text(switch (HandlerNames.label(context, handler)) {
              final label when value == null => label,
              final label => '$label · at ${value.cursor}',
            }, style: theme.fixedFontStyle),
            roundedTopBorder: false,
            includeTopBorder: false,
          ),
          if (value != null)
            Padding(
              padding: const EdgeInsets.all(densePadding),
              child: Text(
                'frontiers: ${value.frontiers.join(', ')}',
                style: theme.subtleTextStyle,
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(densePadding),
            child: switch (state.valueStatus) {
              LoadStatus.failure => PaneMessage(
                'The call failed: ${state.valueError}',
                onRetry: context.read<TimeTravelCubit>().reloadValue,
              ),
              _ when value == null => const PaneMessage('Loading the value…'),
              _ => ValueTree(
                value.value,
                onRef: context.read<TimeTravelCubit>().select,
              ),
            },
          ),
        ],
      ),
    );
  }
}
