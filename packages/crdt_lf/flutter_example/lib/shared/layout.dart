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
  const AppLayout._({super.key, required this.example, required this.panels});

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
    return _ResponsiveBody(example: example, panels: panels);
  }
}

/// Hosts the responsive switch and keeps each pane's element alive across it.
///
/// Crossing [AppLayout.splitBreakpoint] swaps the side-by-side ([_DesktopAppLayout],
/// a [Row]) and tabbed ([_MobAppLayout], a [TabBarView]) subtrees. Without a
/// stable identity, Flutter would discard and rebuild every pane — destroying
/// any state the panes own (e.g. a per-peer `ChangeNotifierProvider`). Wrapping
/// each [Panel.child] in a [KeyedSubtree] with a [GlobalKey] held in this state
/// makes Flutter reparent the existing element instead of recreating it.
class _ResponsiveBody extends StatefulWidget {
  const _ResponsiveBody({required this.example, required this.panels});

  final String example;
  final List<Panel> panels;

  @override
  State<_ResponsiveBody> createState() => _ResponsiveBodyState();
}

class _ResponsiveBodyState extends State<_ResponsiveBody> {
  final _paneKeys = <GlobalKey>[];

  /// The panels with each child wrapped in a [KeyedSubtree] keyed by a stable
  /// [GlobalKey], so panes survive the layout switch.
  List<Panel> get _keyedPanels {
    final panels = widget.panels;
    while (_paneKeys.length < panels.length) {
      _paneKeys.add(GlobalKey());
    }
    return [
      for (var i = 0; i < panels.length; i++)
        Panel(
          label: panels[i].label,
          child: KeyedSubtree(key: _paneKeys[i], child: panels[i].child),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final panels = _keyedPanels;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= AppLayout.splitBreakpoint) {
          return _DesktopAppLayout(example: widget.example, panels: panels);
        }
        return _MobAppLayout(example: widget.example, panels: panels);
      },
    );
  }
}

/// Wide layout: the panels side by side, separated by dividers.
class _DesktopAppLayout extends AppLayout {
  const _DesktopAppLayout({required super.example, required super.panels})
    : super._();

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
  const _MobAppLayout({required super.example, required super.panels})
    : super._();

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
