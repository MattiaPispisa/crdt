import 'package:flutter/material.dart';

/// Describes a single example: how it is named, what it demonstrates, the
/// route it lives at and how to build it.
///
/// Each app builds its own list of these (wiring the shared example screens to
/// its own sync sessions) and derives both the home page and the route table
/// from it.
class Example {
  /// Creates an example descriptor.
  const Example({
    required this.name,
    required this.description,
    required this.path,
    required this.builder,
  });

  /// Display name.
  final String name;

  /// One-line description of what the example demonstrates.
  final String description;

  /// Route path (used by the router and for navigation).
  final String path;

  /// Builds the example widget.
  final WidgetBuilder builder;
}
