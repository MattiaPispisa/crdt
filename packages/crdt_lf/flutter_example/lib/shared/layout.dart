import 'package:crdt_lf_flutter_example/shared/network_settings.dart';
import 'package:flutter/material.dart';

class AppLayout extends StatelessWidget {
  const AppLayout({
    super.key,
    required this.example,
    required this.leftBody,
    required this.rightBody,
  });

  final String example;

  final Widget leftBody;
  final Widget rightBody;

  Widget _leading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => Navigator.of(context).pushNamed('/'),
    );
  }

  Widget _padded(Widget child) {
    return Padding(padding: const EdgeInsets.all(8), child: child);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: _leading(context),
        title: Text('CRDT LF: $example'),
        actions: const [NetworkSettings(), SizedBox(width: 8)],
      ),
      body: Row(
        children: [
          Expanded(child: _padded(leftBody)),
          const VerticalDivider(width: 1),
          Expanded(child: _padded(rightBody)),
        ],
      ),
    );
  }
}
