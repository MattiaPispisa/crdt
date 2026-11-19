// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf_devtools_extension/src/application/handlers/handlers_cubit.dart';
import 'package:crdt_lf_devtools_extension/src/application/load_status.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/state/handler_rows.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/widgets/handler_icon.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/widgets/handler_names.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/widgets/keyboard_list.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/widgets/message.dart';
import 'package:devtools_app_shared/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The filter field and the handler list of [HandlersCubit].
class HandlerTree extends StatefulWidget {
  const HandlerTree({super.key});

  /// The text shown when the document has no handler.
  static const String empty = 'No handler yet.';

  /// The text shown when the filter matches no handler.
  static const String noMatch = 'No handler matches.';

  @override
  State<HandlerTree> createState() => _HandlerTreeState();
}

class _HandlerTreeState extends State<HandlerTree> {
  final TextEditingController _filter = TextEditingController();

  bool _closedExpanded = false;

  bool _deletedExpanded = false;

  @override
  void initState() {
    super.initState();
    _filter.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  void _toggle(HandlerGroup group) => setState(() {
    switch (group) {
      case HandlerGroup.open:
        break;
      case HandlerGroup.closed:
        _closedExpanded = !_closedExpanded;
      case HandlerGroup.deleted:
        _deletedExpanded = !_deletedExpanded;
    }
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(densePadding),
          child: DevToolsClearableTextField(
            controller: _filter,
            hintText: 'Filter by id, name or type',
          ),
        ),
        Expanded(
          child: BlocBuilder<HandlersCubit, HandlersState>(
            builder: (context, state) {
              final handlers = state.handlers;
              if (handlers == null) {
                return state.status == LoadStatus.failure
                    ? PaneMessage(
                      'The call failed: ${state.error}',
                      onRetry: context.read<HandlersCubit>().refresh,
                    )
                    : const PaneMessage('Loading handlers…');
              }
              if (handlers.open.isEmpty &&
                  handlers.closed.isEmpty &&
                  handlers.deleted.isEmpty) {
                return const PaneMessage(HandlerTree.empty);
              }
              final rows = handlerRows(
                handlers,
                filter: _filter.text,
                names: HandlerNames.of(context),
                closedExpanded: _closedExpanded,
                deletedExpanded: _deletedExpanded,
              );
              if (rows.every((r) => r is GroupRow && r.count == 0)) {
                return const PaneMessage(HandlerTree.noMatch);
              }
              return KeyboardList(
                itemCount: rows.length,
                itemBuilder: (context, i) => _row(context, rows[i], state),
                selectedIndex: () {
                  final id = context.read<HandlersCubit>().state.selectedId;
                  final i = rows.indexWhere((r) => r.id != null && r.id == id);
                  return i < 0 ? null : i;
                },
                canSelect: (i) => rows[i] is! GroupRow,
                onSelect:
                    (i) => context.read<HandlersCubit>().select(rows[i].id),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, HandlerRow row, HandlersState state) {
    final theme = Theme.of(context);
    final subtle = theme.subtleTextStyle;
    if (row is GroupRow) {
      final title = switch (row.group) {
        HandlerGroup.open => 'Open',
        HandlerGroup.closed => 'Closed',
        HandlerGroup.deleted => 'Deleted',
      };
      return InkWell(
        onTap: row.group == HandlerGroup.open ? null : () => _toggle(row.group),
        child: Row(
          children: [
            Icon(
              row.expanded ? Icons.expand_more : Icons.chevron_right,
              size: defaultIconSize,
            ),
            const SizedBox(width: densePadding),
            Text('$title (${row.count})', style: theme.regularTextStyle),
          ],
        ),
      );
    }
    final (depth, icon, type, trailing, watched) = switch (row) {
      OpenRow(:final handler, :final depth) => (
        depth + 1,
        handlerIcon(handler.type, container: handler.container),
        handler.type,
        'r${handler.revision} · ${handler.changeCount} changes',
        handler.watched,
      ),
      ClosedRow(:final handler) => (
        1,
        handlerIcon(handler.type),
        handler.type ?? 'unknown type',
        '${handler.changeCount} changes',
        false,
      ),
      _ => (1, Icons.delete_outline, '', '', false),
    };
    final selected = row.id == state.selectedId;
    return Material(
      color:
          selected
              ? theme.colorScheme.primary.withValues(alpha: 0.2)
              : Colors.transparent,
      child: InkWell(
        onTap: () => context.read<HandlersCubit>().select(row.id),
        child: Row(
          children: [
            SizedBox(width: depth * defaultSpacing),
            Icon(icon, size: defaultIconSize),
            const SizedBox(width: densePadding),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      HandlerNames.label(context, row.id!),
                      style: theme.fixedFontStyle,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: densePadding),
                  Flexible(
                    child: Text(
                      type,
                      style: subtle,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            if (watched) ...[
              const Icon(Icons.visibility_outlined, size: defaultIconSize),
              const SizedBox(width: densePadding),
            ],
            Text(trailing, style: subtle),
            const SizedBox(width: densePadding),
          ],
        ),
      ),
    );
  }
}
