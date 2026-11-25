// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';

/// The icon of a handler kind.
///
/// The kind is guessed from [type]: the types of the collection handlers
/// are chosen by the app. An unknown type gets a generic icon.
IconData handlerIcon(String? type, {bool container = false}) {
  final t = (type ?? '').toLowerCase();
  if (container || t.contains('ref')) return Icons.account_tree_outlined;
  if (t.contains('richtext')) return Icons.text_format;
  if (t.contains('text')) return Icons.notes;
  if (t.contains('aggregate')) return Icons.functions;
  if (t.contains('map')) return Icons.data_object;
  if (t.contains('list')) return Icons.format_list_numbered;
  if (t.contains('set')) return Icons.workspaces_outline;
  if (t.contains('register')) return Icons.looks_one_outlined;
  return Icons.extension_outlined;
}
