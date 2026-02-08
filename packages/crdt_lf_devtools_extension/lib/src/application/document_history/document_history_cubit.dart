import 'dart:async';
import 'dart:convert';

import 'package:bloc/bloc.dart';
import 'package:crdt_lf_devtools_extension/src/application/devtools/eval.dart';
import 'package:crdt_lf_devtools_extension/src/application/devtools/event.dart';
import 'package:crdt_lf_devtools_extension/src/application/document_changes/document_changes_cubit.dart';
import 'package:crdt_lf_devtools_extension/src/application/documents/documents_cubit.dart';
import 'package:devtools_app_shared/service.dart' as devtools;
import 'package:equatable/equatable.dart';
import 'package:vm_service/vm_service.dart' as vm_service;

part 'document_history_state.dart';

class DocumentHistoryCubitArgs {
  const DocumentHistoryCubitArgs({
    required this.service,
    required this.document,
  });

  final vm_service.VmService service;
  final TrackedDocument document;
}

/// Cubit driving the History tab.
///
/// Pulls the full timeline from the target via `describeHistoryJson` and
/// owns the cursor position locally — moving the cursor is a pure UI
/// operation (no roundtrip to the VM service required).
class DocumentHistoryCubit extends Cubit<DocumentHistoryState> {
  DocumentHistoryCubit(this.args) : super(DocumentHistoryState.initial()) {
    _load();
    _setupEventSubscription();
  }

  final DocumentHistoryCubitArgs args;

  StreamSubscription<vm_service.Event>? _eventStreamSubscription;
  devtools.Disposable? _alive;

  void _setupEventSubscription() {
    _eventStreamSubscription = args.service.onExtensionEvent.listen((event) {
      if (event.isDocumentChangedEvent &&
          event.documentId == args.document.id) {
        _load();
      }
    });
  }

  Future<void> _load() async {
    if (state.loading) return;

    emit(state.copyWith(loading: true, error: null));

    try {
      _alive?.dispose();
      _alive = devtools.Disposable();

      final eval = CrdtLfEvalExtension.setup(args.service);
      final json = await eval.evalDocumentHistoryJson(
        args.document.id,
        _alive,
      );
      final map = jsonDecode(json) as Map<String, dynamic>;

      if (map.containsKey('error')) {
        throw StateError(map['error'] as String);
      }

      final length = map['length'] as int;
      final changes = (map['changes'] as List<dynamic>)
          .map((e) => ChangeDescriptor.fromJson(e as Map<String, dynamic>))
          .toList();

      // Keep the previous cursor when possible; otherwise show full state.
      final cursor =
          state.cursor != null && state.cursor! <= length ? state.cursor! : length;

      emit(
        DocumentHistoryState(
          loading: false,
          error: null,
          length: length,
          changes: changes,
          cursor: cursor,
        ),
      );
    } catch (e) {
      emit(state.copyWith(loading: false, error: e.toString()));
    }
  }

  /// Move the cursor; clamped to [0, length].
  void setCursor(int cursor) {
    final length = state.length;
    if (length == null) return;
    final clamped = cursor.clamp(0, length);
    if (clamped == state.cursor) return;
    emit(state.copyWith(cursor: clamped));
  }

  void next() {
    final c = state.cursor;
    if (c == null) return;
    setCursor(c + 1);
  }

  void previous() {
    final c = state.cursor;
    if (c == null) return;
    setCursor(c - 1);
  }

  @override
  Future<void> close() {
    _alive?.dispose();
    _eventStreamSubscription?.cancel();
    return super.close();
  }
}
