import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bloc/bloc.dart';
import 'package:crdt_lf/crdt_lf.dart' as crdt_lf;
import 'package:crdt_lf_devtools_extension/src/application/devtools/eval.dart';
import 'package:crdt_lf_devtools_extension/src/application/devtools/event.dart';
import 'package:crdt_lf_devtools_extension/src/application/documents/documents_cubit.dart';
import 'package:devtools_app_shared/service.dart' as devtools;
import 'package:equatable/equatable.dart';
import 'package:vm_service/vm_service.dart' as vm_service;

part 'document_changes_state.dart';

class DocumentChangesCubitArgs {
  const DocumentChangesCubitArgs({
    required this.service,
    required this.document,
  });

  final vm_service.VmService service;
  final TrackedDocument document;
}

/// Cubit loading the change list of a single tracked document.
///
/// Reloads automatically whenever the target emits
/// `crdt_lf:document:changed` for [args.document].
class DocumentChangesCubit extends Cubit<DocumentChangesState> {
  DocumentChangesCubit(this.args) : super(DocumentChangesState.initial()) {
    _load();
    _setupEventSubscription();
  }

  final DocumentChangesCubitArgs args;

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
      final json = await eval.evalDocumentChangesJson(args.document.id, _alive);

      final descriptors =
          (jsonDecode(json) as List<dynamic>)
              .map((e) => ChangeDescriptor.fromJson(e as Map<String, dynamic>))
              .toList();

      emit(
        DocumentChangesState(changes: descriptors, error: null, loading: false),
      );
    } catch (e) {
      emit(state.copyWith(error: e.toString(), loading: false));
    }
  }

  @override
  Future<void> close() {
    _alive?.dispose();
    _eventStreamSubscription?.cancel();
    return super.close();
  }
}
