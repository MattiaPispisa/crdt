import 'package:flutter/material.dart';

class AppError extends StatelessWidget {
  const AppError({super.key, required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(error),
    );
  }
}
