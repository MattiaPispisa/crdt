import 'package:flutter/material.dart';
import 'package:flutter_example/_router.dart';

class _DocumentItem {
  const _DocumentItem({required this.id, required this.name});

  final String id;
  final String name;
}

final availableDocuments = <_DocumentItem>[
  _DocumentItem(id: "30669830-9256-4320-9ed5-f1860cd47d9f", name: "Document 1"),
];

class DocumentsListPage extends StatelessWidget {
  const DocumentsListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Documents')),
      body: ListView.builder(
        itemCount: availableDocuments.length,
        itemBuilder: (context, index) {
          return _item(context, availableDocuments[index]);
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          context.goToUser();
        },
        child: const Icon(Icons.person),
      ),
    );
  }

  Widget _item(BuildContext context, _DocumentItem item) {
    return ListTile(
      title: Text(item.name),
      onTap: () {
        context.goToDocument(item.id);
      },
    );
  }
}
