import 'package:flutter/material.dart';

class ExtensionStatus extends StatelessWidget {
  const ExtensionStatus({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Banner(
      message: 'ALPHA',
      textDirection: TextDirection.ltr,
      location: BannerLocation.topEnd,
      child: child,
    );
  }
}
