import 'package:crdt_lf_devtools_extension/src/application/application.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/ui/widgets/common/extension_status.dart';
import 'package:crdt_lf_devtools_extension/src/presentation/ui/widgets/layout/data_builder.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:vm_service/vm_service.dart';

/// Loads the VM service and the documents
class Bootstrap extends StatelessWidget {
  const Bootstrap({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ExtensionStatus(
      child: BlocProvider(
        create: (_) => VmServiceCubit(),
        child: BlocBuilder<VmServiceCubit, VmServiceState>(
          builder: (context, state) {
            return AppDataBuilder<VmService>(
              data: state.service,
              error: state.error,
              loading: state.loading,
              builder: (context, vmService) {
                return BlocProvider(
                  create: (context) => DocumentsCubit(
                    DocumentsCubitArgs(service: vmService),
                  ),
                  child: child,
                );
              },
            );
          },
        ),
      ),
    );
  }
}
