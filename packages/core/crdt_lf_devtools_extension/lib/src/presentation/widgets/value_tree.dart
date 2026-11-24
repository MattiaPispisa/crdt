// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:crdt_lf_devtools_extension/src/presentation/widgets/handler_names.dart';
import 'package:devtools_app_shared/ui.dart';
import 'package:flutter/material.dart';

/// Draws a value node of the `crdt_lf` DevTools protocol.
///
/// Collections and objects below [expandedDepth] are collapsed, and below
/// the first level when they would show more than [maxExpandedRows] rows; a
/// tap on one overrides it. A collection cut by the app ends with a
/// "… n more" line.
class ValueTree extends StatelessWidget {
  const ValueTree(this.node, {this.onRef, super.key});

  final Object? node;

  /// Called with the handler id when a `ref` node is tapped.
  final ValueChanged<String>? onRef;

  /// The depth from which nested nodes are collapsed.
  static const int expandedDepth = 2;

  /// The most rows of the second level that are shown expanded.
  static const int maxExpandedRows = 200;

  @override
  Widget build(BuildContext context) => _NodeView(
    node: node,
    depth: 0,
    expandedDepth: _expandedRows(node) > maxExpandedRows ? 1 : expandedDepth,
    onRef: onRef,
  );

  static int _expandedRows(Object? node) {
    var rows = 0;
    for (final child in _children(node)) {
      rows += _children(child).length;
    }
    return rows;
  }
}

Iterable<Object?> _children(Object? node) => switch (_kind(node)) {
  'list' || 'set' => _list(node, 'items'),
  'map' => _list(
    node,
    'entries',
  ).cast<List<Object?>>().map((entry) => entry[1]),
  'object' => [if (_map(node)['json'] case final json?) json],
  _ => const [],
};

String? _kind(Object? node) => switch (node) {
  {r'$t': final String kind} => kind,
  _ => null,
};

Map<Object?, Object?> _map(Object? node) => node! as Map<Object?, Object?>;

List<Object?> _list(Object? node, String key) =>
    _map(node)[key]! as List<Object?>;

class _NodeView extends StatefulWidget {
  const _NodeView({
    required this.node,
    required this.depth,
    required this.expandedDepth,
    required this.onRef,
  });

  final Object? node;

  final int depth;

  final int expandedDepth;

  final ValueChanged<String>? onRef;

  @override
  State<_NodeView> createState() => _NodeViewState();
}

class _NodeViewState extends State<_NodeView> {
  // What the user chose; `null` before the first tap.
  bool? _toggled;

  bool get _expanded => _toggled ?? widget.depth < widget.expandedDepth;

  Object? get node => widget.node;

  Widget _child(Object? node) => _NodeView(
    node: node,
    depth: widget.depth + 1,
    expandedDepth: widget.expandedDepth,
    onRef: widget.onRef,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fixed = theme.fixedFontStyle;
    final subtle = theme.subtleTextStyle;
    switch (_kind(node)) {
      case null:
        return switch (node) {
          final String text => Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '"$text"', style: fixed),
                TextSpan(text: '  length ${text.length}', style: subtle),
              ],
            ),
          ),
          _ => Text('$node', style: fixed),
        };
      case 'double':
        return Text('${_map(node)['v']}', style: fixed);
      case 'string':
        final map = _map(node);
        final head = map['head']! as String;
        final length = map['length']! as int;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  // No closing quote: the app cut the string.
                  TextSpan(text: '"$head', style: fixed),
                  TextSpan(text: '  length $length', style: subtle),
                ],
              ),
            ),
            _More(length - head.length),
          ],
        );
      case 'list' || 'set':
        final list = _kind(node) == 'list';
        final items = _list(node, 'items');
        final length = _map(node)['length']! as int;
        return _collapsible('${_kind(node)} · $length items', [
          for (final (i, item) in items.indexed)
            _row(list ? '[$i]' : '•', _child(item)),
          if (length > items.length) _More(length - items.length),
        ]);
      case 'map':
        final entries = _list(node, 'entries');
        final length = _map(node)['length']! as int;
        return _collapsible('map · $length entries', [
          for (final entry in entries.cast<List<Object?>>())
            _entry(entry[0], entry[1]),
          if (length > entries.length) _More(length - entries.length),
        ]);
      case 'ref':
        final map = _map(node);
        final id = map['id']! as String;
        return Wrap(
          spacing: densePadding,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            InkWell(
              onTap: widget.onRef == null ? null : () => widget.onRef!(id),
              child: Text(
                '→ ${HandlerNames.label(context, id)}',
                style: fixed.copyWith(
                  color: theme.colorScheme.primary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
            Text('(${map['type']})', style: subtle),
          ],
        );
      case 'span':
        final map = _map(node);
        final attributes = map['attributes'];
        final embed = map['embed'];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (map['text'] case final String text)
              Text('"$text"', style: fixed)
            else
              _child(map['text']),
            if (_kind(attributes) == 'map')
              Wrap(
                spacing: densePadding,
                runSpacing: densePadding,
                children: [
                  for (final entry
                      in _list(attributes, 'entries').cast<List<Object?>>())
                    RoundedLabel(
                      labelText: '${_inline(entry[0])}: ${_inline(entry[1])}',
                    ),
                ],
              ),
            if (embed != null) _row('embed', _child(embed)),
          ],
        );
      case 'bytes':
        final map = _map(node);
        final length = map['length']! as int;
        final head = map['head']! as String;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('bytes · length $length', style: subtle),
            Text(head, style: fixed),
            _More(length - head.length ~/ 2),
          ],
        );
      case 'object':
        final map = _map(node);
        final type = map['type']! as String;
        if (!map.containsKey('json')) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(type, style: subtle),
              Text('${map['text']}', style: fixed),
            ],
          );
        }
        return _collapsible(type, [_child(map['json'])]);
      case 'more':
        return Text('… deeper levels not loaded', style: subtle);
      case final kind:
        return Text('$kind: $node', style: fixed);
    }
  }

  String _inline(Object? node) => switch (node) {
    final String text => text,
    {r'$t': 'ref', 'id': final String id} =>
      '→ ${HandlerNames.label(context, id)}',
    {r'$t': _} => '…',
    _ => '$node',
  };

  Widget _entry(Object? key, Object? value) {
    if (_kind(key) == null || _kind(key) == 'double') {
      return _row(_inline(key), _child(value));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [_row('key', _child(key)), _row('value', _child(value))],
    );
  }

  Widget _row(String label, Widget child) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('$label: ', style: Theme.of(context).subtleTextStyle),
      Expanded(child: child),
    ],
  );

  Widget _collapsible(String title, List<Widget> children) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _toggled = !_expanded),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _expanded ? Icons.expand_more : Icons.chevron_right,
                size: defaultIconSize,
              ),
              Flexible(child: Text(title, style: theme.subtleTextStyle)),
            ],
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(left: defaultSpacing),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
      ],
    );
  }
}

class _More extends StatelessWidget {
  const _More(this.count);

  final int count;

  @override
  Widget build(BuildContext context) =>
      count > 0
          ? Text('… $count more', style: Theme.of(context).subtleTextStyle)
          : const SizedBox.shrink();
}
