import 'package:crdt_lf_flutter_example/shared/app_bar_links.dart';
import 'package:crdt_lf_flutter_example/shared/network_settings.dart';
import 'package:flutter/material.dart';

/// A labelled pane shown by [AppLayout].
///
/// [label] is used as the tab title in the narrow/tabbed layout; [child] is the
/// pane content (typically a peer's document view).
class Panel {
  /// Creates a panel with its [child] content and tab [label].
  const Panel({required this.child, required this.label});

  /// The pane content.
  final Widget child;

  /// The tab title (shown only in the tabbed/mobile layout).
  final String label;
}

/// Multi-pane layout for an example (one [Panel] per peer).
///
/// Responsive: on wide screens the panels sit side by side
/// ([_DesktopAppLayout]); on phones/tablets they become swipeable tabs
/// ([_MobAppLayout]). Construct it through the [AppLayout] factory, which picks
/// the right one for the available width.
abstract class AppLayout extends StatelessWidget {
  const AppLayout._({
    super.key,
    required this.example,
    required this.panels,
  });

  /// Builds the layout that fits the current screen width: panels side by side
  /// on wide screens, swipeable tabs on phones/tablets.
  const factory AppLayout({
    Key? key,
    required String example,
    required List<Panel> panels,
  }) = _ResponsiveAppLayout;

  /// Below this width (logical px) the panels are shown as tabs instead of
  /// side by side.
  static const double splitBreakpoint = 840;

  /// Name of the example (shown in the app bar title).
  final String example;

  /// The panes to display, in order.
  final List<Panel> panels;

  Widget _leading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => Navigator.of(context).pop(),
    );
  }

  /// Wraps a pane with the shared padding.
  Widget padded(Widget child) {
    return Padding(padding: const EdgeInsets.all(8), child: child);
  }

  /// The app bar shared by both layouts; [bottom] hosts the [TabBar] on mobile.
  AppBar buildAppBar(BuildContext context, {PreferredSizeWidget? bottom}) {
    return AppBar(
      leading: _leading(context),
      title: Text('CRDT LF: $example'),
      actions: const [NetworkSettings(), AppBarLinks(), SizedBox(width: 8)],
      bottom: bottom,
    );
  }
}

/// Picks [_DesktopAppLayout] or [_MobAppLayout] based on the available width.
class _ResponsiveAppLayout extends AppLayout {
  const _ResponsiveAppLayout({
    super.key,
    required super.example,
    required super.panels,
  }) : super._();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= AppLayout.splitBreakpoint) {
          return _DesktopAppLayout(example: example, panels: panels);
        }
        return _MobAppLayout(example: example, panels: panels);
      },
    );
  }
}

/// Wide layout: the panels side by side, separated by dividers.
class _DesktopAppLayout extends AppLayout {
  const _DesktopAppLayout({
    required super.example,
    required super.panels,
  }) : super._();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: buildAppBar(context),
      body: Row(
        children: [
          for (var i = 0; i < panels.length; i++) ...[
            if (i > 0) const VerticalDivider(width: 1),
            Expanded(child: padded(panels[i].child)),
          ],
        ],
      ),
    );
  }
}

/// Narrow layout (phone/tablet): the panels as swipeable tabs.
class _MobAppLayout extends AppLayout {
  const _MobAppLayout({
    required super.example,
    required super.panels,
  }) : super._();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: panels.length,
      child: Scaffold(
        appBar: buildAppBar(
          context,
          bottom: TabBar(
            tabs: [
              for (final panel in panels) Tab(text: panel.label),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            for (final panel in panels) padded(panel.child),
          ],
        ),
      ),
    );
  }
}
