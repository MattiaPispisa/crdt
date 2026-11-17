// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

import 'dart:async';

import 'package:crdt_lf_devtools_extension/src/application/handlers/handler_value_cubit.dart';
import 'package:crdt_lf_devtools_extension/src/application/handlers/handlers_cubit.dart';
import 'package:crdt_lf_devtools_extension/src/bridge/crdt_lf_client.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/state/handler_detail.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/state/handler_tree.dart';
import 'package:devtools_app_shared/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The handlers of the document [doc], and the value of the selected one.
class StateTab extends StatefulWidget {
  const StateTab({required this.doc, super.key});

  /// The tracked id of the document.
  final int doc;

  @override
  State<StateTab> createState() => _StateTabState();
}

class _StateTabState extends State<StateTab> {
  late final HandlersCubit _handlers;

  late final HandlerValueCubit _value;

  @override
  void initState() {
    super.initState();
    final client = context.read<CrdtLfClient>();
    _handlers = HandlersCubit(client, widget.doc);
    _value = HandlerValueCubit(client, widget.doc);
  }

  @override
  void dispose() {
    unawaited(_handlers.close());
    unawaited(_value.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: _handlers),
        BlocProvider.value(value: _value),
      ],
      child: BlocListener<HandlersCubit, HandlersState>(
        listenWhen: (a, b) => a.selectedOpen?.id != b.selectedOpen?.id,
        listener: (context, state) => _value.select(state.selectedOpen?.id),
        child: SplitPane(
          axis: Axis.horizontal,
          initialFractions: const [0.4, 0.6],
          children: const [HandlerTree(), HandlerDetail()],
        ),
      ),
    );
  }
}
