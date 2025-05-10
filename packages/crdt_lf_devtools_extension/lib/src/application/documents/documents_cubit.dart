import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:crdt_lf_devtools_extension/src/application/devtools/eval.dart';
import 'package:crdt_lf_devtools_extension/src/application/devtools/event.dart';
import 'package:devtools_app_shared/service.dart';
import 'package:equatable/equatable.dart';
import 'package:vm_service/vm_service.dart';

part 'documents_state.dart';

class DocumentsCubitArgs {
  final VmService service;

  DocumentsCubitArgs({required this.service});
}

/// Cubit for loading the documents from the VM service
///
/// This cubit listens for document created events and loads the documents from the
/// VM service.
class DocumentsCubit extends Cubit<DocumentsState> {
  DocumentsCubit(this.args) : super(DocumentsState.initial()) {
    load();
    _setupEventSubscription();
  }

  final DocumentsCubitArgs args;
  Disposable? _alive;
  StreamSubscription<Event>? _eventStreamSubscription;

  void _setupEventSubscription() {
    _eventStreamSubscription = args.service.onExtensionEvent.listen((event) {
      if (event.isDocumentCreatedEvent) {
        load();
      }
    });
  }

  void load() async {
    if (state.loading) {
      return;
    }

    try {
      emit(
        DocumentsState(
          loading: true,
          documents: state.documents,
          error: null,
          selectedDocument: state.selectedDocument,
        ),
      );

      _alive?.dispose();
      _alive = Disposable();

      final eval = CrdtLfEvalExtension.setup(args.service);

      final result = await eval.evalDocuments(_alive);

      final trackedDocuments = await Future.wait(
        result.elements!.cast<InstanceRef>().map((element) async {
          final trackedDocumentInstance = await eval.safeGetInstance(
            element,
            _alive,
          );
          final idField = trackedDocumentInstance.fields!.firstWhere(
            (f) => f.name == 'id',
          );
          final documentField = trackedDocumentInstance.fields!.firstWhere(
            (f) => f.name == 'document',
          );

          final responses = await Future.wait([
            eval.safeGetInstance(idField.value, _alive),
            eval.safeGetInstance(documentField.value, _alive),
          ]);

          return TrackedDocument(
            id: int.parse(responses[0].valueAsString!),
            document: responses[1],
          );
        }),
      );

      var selectedDocument = state.selectedDocument;

      if (state.selectedDocument != null &&
          !_exists(trackedDocuments, selectedDocument!.id)) {
        selectedDocument = null;
      }

      emit(
        DocumentsState(
          loading: false,
          documents: trackedDocuments,
          selectedDocument: selectedDocument,
          error: null,
        ),
      );
    } catch (e) {
      emit(
        DocumentsState(
          loading: false,
          error: e.toString(),
          documents: null,
          selectedDocument: null,
        ),
      );
    }
  }

  bool _exists(List<TrackedDocument>? documents, int documentId) {
    return documents?.any((d) => d.id == documentId) ?? false;
  }

  void select(int? id) {
    if (id == null) {
      return emit(
        DocumentsState(
          selectedDocument: null,
          documents: state.documents,
          loading: state.loading,
          error: state.error,
        ),
      );
    }

    if (_exists(state.documents, id)) {
      emit(
        state.copyWith(
          selectedDocument: state.documents?.firstWhere((d) => d.id == id),
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
