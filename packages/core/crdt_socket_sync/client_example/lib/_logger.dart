import 'package:en_logger/en_logger.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class LoggerProvider extends StatelessWidget {
  const LoggerProvider({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Provider(
      create:
          (_) => EnLogger(defaultPrefixFormat: const PrefixFormat.snakeSquare())
            ..addHandler(PrinterHandler(writeIfNotContains: ['PongMessage'])),
      child: child,
    );
  }
}

extension LoggerProviderHelper on BuildContext {
  EnLogger logger() => Provider.of<EnLogger>(this, listen: false);
  EnLogger loggerInstance(String prefix) =>
      logger().getConfiguredInstance(prefix: prefix);
}
