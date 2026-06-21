import 'package:flutter/material.dart';

import 'examples/examples.dart';

/// Application routes, derived from [kExamples] plus the home page.
final kRoutes = <String, WidgetBuilder>{
  '/': (context) => const Examples(),
  for (final example in kExamples) example.path: example.builder,
};
