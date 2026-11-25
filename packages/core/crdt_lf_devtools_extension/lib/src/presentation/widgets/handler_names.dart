// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// The debug names of the handlers of the selected document, by id.
class HandlerNames extends InheritedWidget {
  const HandlerNames({required this.names, required super.child, super.key});

  final Map<String, String> names;

  /// The closest names; empty when there is none.
  static Map<String, String> of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HandlerNames>()?.names ??
      const {};

  /// The debug name of [id], or [id] when it has none.
  static String label(BuildContext context, String id) => of(context)[id] ?? id;

  @override
  bool updateShouldNotify(HandlerNames oldWidget) =>
      !mapEquals(names, oldWidget.names);
}
