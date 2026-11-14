// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// A back arrow that pops the app router, for the `leading` of an [AppBar].
///
/// The [AppBar] adds a back arrow by itself only when its own navigator has a
/// page below. The first page of a shell route has none there, even with Home
/// below the shell: use this button on such a page.
class RouterBackButton extends StatelessWidget {
  /// Creates a back arrow that pops the app router.
  const RouterBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    return BackButton(onPressed: context.pop);
  }
}
