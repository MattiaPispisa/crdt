// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf/crdt_lf.dart';
import 'package:crdt_lf_devtools_extension/src/application/events/event_log_cubit.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/models/models.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/widgets/keyboard_list.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/widgets/message.dart';
import 'package:devtools_app_shared/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The event log of the document in [EventLogCubit]: the Record toggle,
/// the list and the detail of the selected event.
class EventsTab extends StatelessWidget {
  const EventsTab({required this.onChange, super.key});

  /// Called with a change id the user taps in the detail.
  final ValueChanged<OperationId> onChange;

  /// The note under the Record toggle.
  static const String recordingNote =
      'While recording, the app builds one event per move of the document.';

  /// The text shown when the list is empty.
  static const String empty = 'No event yet. Turn on Record to start.';

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<EventLogCubit>();
    final state = cubit.state;
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(densePadding),
          child: Row(
            children: [
              DevToolsToggleButton(
                icon: Icons.fiber_manual_record,
                label: 'Record',
                message: 'Record the events of the document',
                isSelected: state.recording,
                onPressed:
                    () => cubit.setRecording(recording: !state.recording),
              ),
              const SizedBox(width: denseSpacing),
              DevToolsButton(
                icon: Icons.block,
                label: 'Clear',
                onPressed: state.events.isEmpty ? null : cubit.clear,
              ),
              const SizedBox(width: denseSpacing),
              Text('${state.events.length}', style: theme.subtleTextStyle),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: densePadding),
          child: Text(recordingNote, style: theme.subtleTextStyle),
        ),
        if (state.error case final error?)
          PaneMessage(
            'The call failed: $error',
            onRetry: () => cubit.setRecording(recording: !state.recording),
          ),
        const SizedBox(height: densePadding),
        Expanded(
          child: SplitPane(
            axis: Axis.horizontal,
            initialFractions: const [0.5, 0.5],
            children: [
              if (state.events.isEmpty)
                const PaneMessage(empty)
              else
                _EventList(state: state),
              _EventDetail(event: state.selected, onChange: onChange),
            ],
          ),
        ),
      ],
    );
  }
}

/// The local wall time `HH:mm:ss.SSS` of [time].
String timeLabel(DateTime time) {
  final t = time.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}:${two(t.second)}.'
      '${t.millisecond.toString().padLeft(3, '0')}';
}

class _EventList extends StatelessWidget {
  const _EventList({required this.state});

  final EventLogState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cubit = context.read<EventLogCubit>();
    final events = state.events;
    return KeyboardList(
      itemCount: events.length,
      selectedIndex: () {
        final n = cubit.state.selectedN;
        final i = events.indexWhere((e) => e.n == n);
        return i < 0 ? null : i;
      },
      onSelect: (i) => cubit.select(events[i].n),
      itemBuilder: (context, i) {
        final event = state.events[i];
        final selected = event.n == state.selectedN;
        return Material(
          color:
              selected
                  ? theme.colorScheme.primary.withValues(alpha: 0.2)
                  : Colors.transparent,
          child: InkWell(
            onTap: () => cubit.select(event.n),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: densePadding),
              child: Row(
                children: [
                  SizedBox(
                    width: 100,
                    child: Text(
                      timeLabel(event.time),
                      style: theme.fixedFontStyle,
                    ),
                  ),
                  SizedBox(
                    width: 80,
                    child: Text(event.type, style: theme.regularTextStyle),
                  ),
                  SizedBox(
                    width: 80,
                    child: Text(
                      event.source ?? event.reason ?? '',
                      style: theme.subtleTextStyle,
                    ),
                  ),
                  SizedBox(
                    width: 50,
                    child: Text('${event.count}', style: theme.fixedFontStyle),
                  ),
                  Expanded(
                    child: Text(
                      event.origin ?? '',
                      style: theme.subtleTextStyle,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _EventDetail extends StatelessWidget {
  const _EventDetail({required this.event, required this.onChange});

  final DocumentLogEvent? event;

  final ValueChanged<OperationId> onChange;

  @override
  Widget build(BuildContext context) {
    final event = this.event;
    if (event == null) return const PaneMessage('Select an event.');
    final theme = Theme.of(context);
    final fields = [
      ('n', '${event.n}'),
      ('time', timeLabel(event.time)),
      ('type', event.type),
      ('source', event.source ?? '-'),
      ('reason', event.reason ?? '-'),
      ('count', '${event.count}'),
      ('removed', '${event.removed}'),
      ('rewritten', '${event.rewritten}'),
      ('snapshotId', event.snapshotId ?? '-'),
      ('origin', event.origin ?? '-'),
    ];
    return SelectionArea(
      child: ListView(
        children: [
          AreaPaneHeader(
            title: Text('Event ${event.n}'),
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
          if (event.ids.isNotEmpty) ...[
            AreaPaneHeader(
              title: Text(
                event.ids.length < event.count
                    ? 'Changes (first ${event.ids.length} of ${event.count})'
                    : 'Changes',
              ),
              roundedTopBorder: false,
            ),
            for (final id in event.ids)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: densePadding),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: InkWell(
                    onTap: () => onChange(OperationId.parse(id)),
                    child: Text(
                      '→ $id',
                      style: theme.fixedFontStyle.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
