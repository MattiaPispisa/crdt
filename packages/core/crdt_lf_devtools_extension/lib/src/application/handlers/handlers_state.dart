// Copyright 2025 Mattia Pispisa
// SPDX-License-Identifier: MIT

part of 'handlers_cubit.dart';

/// The handlers of a document and the selected id.
class HandlersState extends Equatable {
  const HandlersState({
    this.status = LoadStatus.initial,
    this.handlers,
    this.selectedId,
    this.error,
  });

  final LoadStatus status;

  /// The last loaded list; `null` before the first load.
  final HandlerList? handlers;

  /// The selected handler id, in any group; `null` when there is none.
  final String? selectedId;

  /// The error of the last load; `null` unless [status] is a failure.
  final String? error;

  /// The selected handler when it is open; `null` otherwise.
  HandlerSummary? get selectedOpen =>
      handlers?.open.where((h) => h.id == selectedId).firstOrNull;

  /// The selected handler when it is closed; `null` otherwise.
  ClosedHandler? get selectedClosed =>
      handlers?.closed.where((h) => h.id == selectedId).firstOrNull;

  /// Whether the selected handler is deleted.
  bool get selectedDeleted =>
      selectedId != null && (handlers?.deleted.contains(selectedId) ?? false);

  HandlersState _copyWith({
    LoadStatus? status,
    String? Function()? selectedId,
    String? Function()? error,
  }) => HandlersState(
    status: status ?? this.status,
    handlers: handlers,
    selectedId: selectedId == null ? this.selectedId : selectedId(),
    error: error == null ? this.error : error(),
  );

  @override
  List<Object?> get props => [status, handlers, selectedId, error];
}
