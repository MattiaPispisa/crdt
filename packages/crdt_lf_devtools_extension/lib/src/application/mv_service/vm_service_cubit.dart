import 'package:bloc/bloc.dart';
import 'package:devtools_extensions/devtools_extensions.dart';
import 'package:equatable/equatable.dart';
import 'package:vm_service/vm_service.dart';

part 'vm_service_state.dart';

class VmServiceCubit extends Cubit<VmServiceState> {
  VmServiceCubit() : super(VmServiceState.initial()) {
    _observeState();
  }

  _observeState() {
    serviceManager.connectedState.addListener(_onConnectedStateChange);
  }

  _onConnectedStateChange() {
    final connectedState = serviceManager.connectedState.value;

    if (connectedState.connected) {
      return emit(
        state.copyWith(loading: false, service: serviceManager.service!),
      );
    }

    return emit(
      state.copyWith(loading: false, error: 'Not connected to a VM'),
    );
  }

  @override
  Future<void> close() {
    serviceManager.connectedState.removeListener(_onConnectedStateChange);
    return super.close();
  }
}
