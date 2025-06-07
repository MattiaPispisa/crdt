import 'package:flutter/material.dart';
import 'package:flutter_example/_router.dart';

class DocumentItem {
  const DocumentItem({required this.id, required this.name});

  final String id;
  final String name;
}

final availableDocuments = <DocumentItem>[
  DocumentItem(id: "30669830-9256-4320-9ed5-f1860cd47d9f", name: "Document 1"),
];

class DocumentsList extends StatelessWidget {
  const DocumentsList({super.key});

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
    );
  }

  Widget _item(BuildContext context, DocumentItem item) {
    return ListTile(
      title: Text(item.name),
      onTap: () {
        context.goToDocument(item.id);
      },
    );
  }
}
