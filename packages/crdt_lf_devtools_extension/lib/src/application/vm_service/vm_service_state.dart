part of 'vm_service_cubit.dart';

class VmServiceState extends Equatable {
  final bool loading;
  final String? error;
  final VmService? service;

  const VmServiceState({
    required this.loading,
    required this.error,
    required this.service,
  });

  factory VmServiceState.initial() {
    return const VmServiceState(
      loading: false,
      error: null,
      service: null,
    );
  }

  VmServiceState copyWith({
    bool? loading,
    String? error,
    VmService? service,
  }) {
    return VmServiceState(
      loading: loading ?? this.loading,
      error: error ?? this.error,
      service: service ?? this.service,
    );
  }

  @override
  List<Object?> get props => [loading, error, service];
}
