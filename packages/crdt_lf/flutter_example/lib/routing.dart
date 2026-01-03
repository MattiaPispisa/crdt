import 'package:flutter/material.dart';

import 'examples/examples.dart';
import 'todo_list/todo_list.dart';

typedef RouteBuilder = Widget Function(BuildContext context);

class RouteData {
  const RouteData({
    required this.path,
    required this.name,
    required this.builder,
  });

  final String path;
  final String name;
  final RouteBuilder builder;
}

final kExampleRoutes = [
  RouteData(
    path: '/todo-list',
    name: 'Todo List',
    builder: (context) => const TodoList(),
  ),
];

final kRoutes = <String, RouteBuilder>{
  '/': (context) => const Examples(),
  ...{for (var e in kExampleRoutes) e.path: e.builder},
};
