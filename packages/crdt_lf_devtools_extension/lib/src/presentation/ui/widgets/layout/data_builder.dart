import 'package:crdt_lf_devtools_extension/src/presentation/ui/widgets/layout/error.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/ui/widgets/layout/loading.dart';
import 'package:flutter/material.dart';

class AppDataBuilder<T> extends StatelessWidget {
  const AppDataBuilder({
    super.key,
    required this.loading,
    required this.error,
    required this.data,
    required this.builder,
  });

  final String? error;
  final bool loading;
  final T? data;
  final Widget Function(BuildContext context, T data) builder;

  @override
  Widget build(BuildContext context) {
    if (data != null) {
      return builder(context, data as T);
    }

    if (error != null) {
      return AppError(error: error!);
    }
    return const AppLoader();
  }
}
