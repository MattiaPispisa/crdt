import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:flutter/material.dart';
import 'src/dag_visualizer.dart';

void main() {
  runApp(const CrdtLfDevToolsExtension());
}

class CrdtLfDevToolsExtension extends StatelessWidget {
  const CrdtLfDevToolsExtension({super.key});

  @override
  Widget build(BuildContext context) {
    return const DevToolsExtension(
      child: CrdtLfExtensionBody(),
    );
  }
}

class CrdtLfExtensionBody extends StatelessWidget {
  const CrdtLfExtensionBody({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('CRDT LF Document Visualizer'),
        ),
        body: const DAGVisualizer(),
      ),
    );
  }
}
