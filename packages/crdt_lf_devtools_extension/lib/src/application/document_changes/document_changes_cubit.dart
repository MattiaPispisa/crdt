import 'dart:async';
import 'dart:convert';

import 'package:bloc/bloc.dart';
import 'package:crdt_lf_devtools_extension/src/application/devtools/eval.dart';
import 'package:crdt_lf_devtools_extension/src/application/devtools/event.dart';
import 'package:crdt_lf_devtools_extension/src/application/documents/documents_cubit.dart';

import 'package:crdt_lf/crdt_lf.dart' as crdt_lf;

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

/// Cubit for loading the changes of a document
///
/// This cubit listens for changes to the document and loads the changes from the
/// VM service.
class DocumentChangesCubit extends Cubit<DocumentChangesState> {
  DocumentChangesCubit(this.args) : super(DocumentChangesState.initial()) {
    _loadDocumentChanges();
    _setupEventSubscription();
  }

  final DocumentChangesCubitArgs args;

  StreamSubscription<vm_service.Event>? _eventStreamSubscription;
  devtools.Disposable? _alive;

  void _setupEventSubscription() {
    _eventStreamSubscription = args.service.onExtensionEvent.listen((event) {
      if (event.isDocumentChangedEvent &&
          event.documentId == args.document.id) {
        _loadDocumentChanges();
      }
    });
  }

  void _loadDocumentChanges() async {
    if (state.loading) {
      return;
    }

    try {
      emit(
        DocumentChangesState(
          loading: true,
          error: null,
          changes: state.changes,
        ),
      );

      _alive?.dispose();
      _alive = devtools.Disposable();

      final eval = CrdtLfEvalExtension.setup(args.service);
      final documentChangesInstance = await eval.evalDocumentChanges(
        args.document,
        _alive,
      );

      final encodedChanges =
          (await eval.service.retrieveFullStringValue(
            eval.isolateRef!.id!,
            documentChangesInstance,
          ))!;

      final descriptors =
          (jsonDecode(encodedChanges) as List<dynamic>)
              .map((e) => crdt_lf.Change.fromJson(e))
              .toList();

      emit(
        DocumentChangesState(changes: descriptors, error: null, loading: false),
      );
    } catch (e) {
      emit(
        DocumentChangesState(
          changes: state.changes,
          error: e.toString(),
          loading: false,
        ),
      );
    }
  }

  @override
  Future<void> close() {
    _alive?.dispose();
    _eventStreamSubscription?.cancel();
    return super.close();
  }
}
