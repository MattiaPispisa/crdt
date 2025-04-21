import 'package:crdt_lf_devtools_extension/src/application/application.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vm_service/vm_service.dart';

extension DevToolsBuildContextHelper on BuildContext {
  VmService get vmService => read<VmServiceCubit>().state.service!;
}
