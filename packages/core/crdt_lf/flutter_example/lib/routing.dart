import 'package:crdt_lf_flutter_example/examples.dart';
import 'package:crdt_lf_flutter_example/generated.dart';
import 'package:flutter/material.dart';
import 'package:shared_examples_infrastructure/shared_examples_infrastructure.dart';

/// Application routes, derived from [kExamples] plus the home page.
final kRoutes = <String, WidgetBuilder>{
  '/':
      (context) => ExamplesHome(
        title: 'CRDT LF Examples',
        logo: Image.asset('assets/images/logo.png', height: 120),
        versions: [
          PackageVersion(name: 'crdt_lf', version: crdt_lf_version),
          PackageVersion(
            name: 'crdt_lf_flutter',
            version: crdt_lf_flutter_version,
          ),
        ],
        examples: kExamples,
        actions: homeActions,
      ),
  for (final example in kExamples) example.path: example.builder,
};
