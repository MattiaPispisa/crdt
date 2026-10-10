import 'package:flutter/material.dart';

class AppError extends StatelessWidget {
  const AppError({required this.error, super.key});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Center(child: Text(error));
  }
}
