import 'package:crdt_lf_flutter_example/shared/network.dart';
import 'package:crdt_lf_flutter_example/todo_list/todo_list.dart';
import 'package:crdt_lf_flutter_example/whiteboard/whiteboard.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => Network(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'CRDT LF Example',
        theme: ThemeData(primarySwatch: Colors.blue),
        initialRoute: '/',
        routes: {
          '/': (context) => const Examples(),
          'todo-list': (context) => const TodoList(),
          'whiteboard': (context) => const Whiteboard(),
        },
      ),
    );
  }
}

class Examples extends StatelessWidget {
  const Examples({super.key});

  Widget _listTile(BuildContext context, String title, String route) {
    return ListTile(
      title: Text(title),
      onTap: () => Navigator.of(context).pushNamed(route),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const SizedBox(),
        title: const Text('CRDT LF Examples'),
      ),
      body: ListView(
        children: [
          _listTile(context, 'Todo List', 'todo-list'),
          _listTile(context, 'Whiteboard', 'whiteboard'),
        ],
      ),
    );
  }
}
