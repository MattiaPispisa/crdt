// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf_devtools_extension/src/bridge/models/models.dart';

/// A group of the handler list.
enum HandlerGroup { open, closed, deleted }

/// A row of the handler list.
sealed class HandlerRow {
  const HandlerRow();

  /// The handler id; `null` for a group row.
  String? get id => null;
}

/// The title row of a group; [count] counts the rows that match the
/// filter.
final class GroupRow extends HandlerRow {
  const GroupRow(this.group, {required this.count, required this.expanded});

  final HandlerGroup group;

  final int count;

  final bool expanded;
}

/// An open handler, [depth] levels under a root.
final class OpenRow extends HandlerRow {
  const OpenRow(this.handler, this.depth);

  final HandlerSummary handler;

  final int depth;

  @override
  String get id => handler.id;
}

/// A handler with data and no instance in the app.
final class ClosedRow extends HandlerRow {
  const ClosedRow(this.handler);

  final ClosedHandler handler;

  @override
  String get id => handler.id;
}

/// A deleted handler.
final class DeletedRow extends HandlerRow {
  const DeletedRow(this.id);

  @override
  final String id;
}

/// The rows of [list]: the open handlers as a tree, then the closed and
/// the deleted ones, each group after its [GroupRow].
///
/// A root is an open handler that no open container lists. A child sits
/// under each container that lists it, and a cycle stops at the first
/// repeat. [filter] matches the id, the debug name in [names] or the type,
/// ignoring case; an open handler also stays when a descendant matches.
List<HandlerRow> handlerRows(
  HandlerList list, {
  String filter = '',
  Map<String, String> names = const {},
  bool closedExpanded = false,
  bool deletedExpanded = false,
}) {
  final needle = filter.trim().toLowerCase();
  bool matches(String id, String? type) =>
      needle.isEmpty ||
      id.toLowerCase().contains(needle) ||
      (names[id]?.toLowerCase().contains(needle) ?? false) ||
      (type?.toLowerCase().contains(needle) ?? false);

  final open = _openRows(list.open, (h) => matches(h.id, h.type));
  final closed = [
    for (final h in list.closed)
      if (matches(h.id, h.type)) ClosedRow(h),
  ];
  final deleted = [
    for (final id in list.deleted)
      if (matches(id, null)) DeletedRow(id),
  ];
  return [
    GroupRow(HandlerGroup.open, count: open.length, expanded: true),
    ...open,
    GroupRow(
      HandlerGroup.closed,
      count: closed.length,
      expanded: closedExpanded,
    ),
    if (closedExpanded) ...closed,
    GroupRow(
      HandlerGroup.deleted,
      count: deleted.length,
      expanded: deletedExpanded,
    ),
    if (deletedExpanded) ...deleted,
  ];
}

List<OpenRow> _openRows(
  List<HandlerSummary> open,
  bool Function(HandlerSummary) matches,
) {
  final byId = {for (final h in open) h.id: h};
  final listed = {
    for (final h in open)
      for (final child in h.children)
        if (child.id != h.id && byId.containsKey(child.id)) child.id,
  };
  final reached = <String>{};

  List<OpenRow> visit(HandlerSummary h, int depth, Set<String> path) {
    reached.add(h.id);
    final children = <OpenRow>[
      for (final child in h.children)
        if (byId[child.id] case final next? when !path.contains(next.id))
          ...visit(next, depth + 1, {...path, next.id}),
    ];
    if (children.isEmpty && !matches(h)) return const [];
    return [OpenRow(h, depth), ...children];
  }

  final rows = <OpenRow>[];
  for (final h in open) {
    if (!listed.contains(h.id)) rows.addAll(visit(h, 0, {h.id}));
  }
  // Handlers listed only inside a cycle have no root: start one there.
  for (final h in open) {
    if (!reached.contains(h.id)) rows.addAll(visit(h, 0, {h.id}));
  }
  return rows;
}
