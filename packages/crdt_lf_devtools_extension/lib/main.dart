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

class CrdtLfExtensionBody extends StatefulWidget {
  const CrdtLfExtensionBody({super.key});

  @override
  State<CrdtLfExtensionBody> createState() => _CrdtLfExtensionBodyState();
}

class _CrdtLfExtensionBodyState extends State<CrdtLfExtensionBody> {
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
        body: !serviceManager.hasConnection
            ? const Center(
                child: Text('Connect to a Dart application to visualize CRDT documents'),
              )
            : const DAGVisualizer(),
      ),
    );
  }
}
