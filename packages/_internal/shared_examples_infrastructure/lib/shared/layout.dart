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
///
/// [title] is the full app-bar title and [actions] are the app-bar trailing
/// widgets — both injected so each app can brand the bar (e.g. a network
/// settings button vs a connection indicator).
abstract class AppLayout extends StatelessWidget {
  const AppLayout._({
    super.key,
    required this.title,
    required this.panels,
    required this.actions,
  });

  /// Builds the layout that fits the current screen width: panels side by side
  /// on wide screens, swipeable tabs on phones/tablets.
  const factory AppLayout({
    Key? key,
    required String title,
    required List<Panel> panels,
    List<Widget> actions,
  }) = _ResponsiveAppLayout;

  /// Below this width (logical px) the panels are shown as tabs instead of
  /// side by side.
  static const double splitBreakpoint = 840;

  /// The app bar title.
  final String title;

  /// The panes to display, in order.
  final List<Panel> panels;

  /// The app bar trailing actions.
  final List<Widget> actions;

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
      title: Text(title),
      actions: [...actions, const SizedBox(width: 8)],
      bottom: bottom,
    );
  }
}

/// Picks [_DesktopAppLayout] or [_MobAppLayout] based on the available width.
///
/// Crossing [AppLayout.splitBreakpoint] swaps the side-by-side
/// ([_DesktopAppLayout], a [Row]) and tabbed ([_MobAppLayout], a [TabBarView])
/// subtrees, which unmounts and rebuilds every pane. That is safe because the
/// per-peer controller state lives *above* this switch (owned by the example
/// scaffold and provided by value), so a rebuilt pane simply re-reads it. We
/// deliberately do **not** try to reparent the live pane elements across the
/// swap (e.g. with a [GlobalKey]): moving a live element between a lazy
/// [TabBarView] and a [Row] during the layout phase leaves dangling render
/// objects and disposed providers ("unmounted" assertions / null provider
/// reads).
class _ResponsiveAppLayout extends AppLayout {
  const _ResponsiveAppLayout({
    super.key,
    required super.title,
    required super.panels,
    super.actions = const [],
  }) : super._();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= AppLayout.splitBreakpoint) {
          return _DesktopAppLayout(
            title: title,
            panels: panels,
            actions: actions,
          );
        }
        return _MobAppLayout(title: title, panels: panels, actions: actions);
      },
    );
  }
}

/// Wide layout: the panels side by side, separated by dividers.
class _DesktopAppLayout extends AppLayout {
  const _DesktopAppLayout({
    required super.title,
    required super.panels,
    required super.actions,
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

/// Keeps [child] alive when it scrolls out of a lazy viewport.
///
/// A [TabBarView] disposes the page that leaves the viewport, which would
/// destroy any state the page owns (e.g. a per-peer `ChangeNotifierProvider`).
/// Wrapping each tab page in this widget marks it to be retained, so switching
/// tabs preserves the pane's state instead of rebuilding it from scratch.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// Narrow layout (phone/tablet): the panels as swipeable tabs.
class _MobAppLayout extends AppLayout {
  const _MobAppLayout({
    required super.title,
    required super.panels,
    required super.actions,
  }) : super._();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: panels.length,
      child: Scaffold(
        appBar: buildAppBar(
          context,
          bottom: TabBar(
            tabs: [for (final panel in panels) Tab(text: panel.label)],
          ),
        ),
        body: TabBarView(
          children: [
            for (final panel in panels) _KeepAlive(child: padded(panel.child)),
          ],
        ),
      ),
    );
  }
}
