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

  DocumentsCubitArgs({
    required this.service,
  });
}

class DocumentsCubit extends Cubit<DocumentsState> {
  DocumentsCubit(this.args) : super(DocumentsState.initial()) {
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
    try {
      emit(DocumentsState(
        loading: true,
        documents: state.documents,
        error: null,
        selectedDocument: state.selectedDocument,
      ));

      _alive?.dispose();
      _alive = Disposable();

      final eval = CrdtLfEvalExtension.setup(args.service);

      final result = await eval.evalDocuments(_alive);

      final trackedDocuments = await Future.wait(
          result.elements!.cast<InstanceRef>().map((element) async {
        final trackedDatabase = await eval.safeGetInstance(element, _alive);
        final idField =
            trackedDatabase.fields!.firstWhere((f) => f.name == 'id');
        final databaseField =
            trackedDatabase.fields!.firstWhere((f) => f.name == 'database');

        final responses = await Future.wait([
          eval.safeGetInstance(idField.value, _alive),
          eval.safeGetInstance(databaseField.value, _alive)
        ]);

        return TrackedDocument(
          id: int.parse(responses[0].valueAsString!),
          document: responses[1],
        );
      }));

      var selectedDocument = state.selectedDocument;

      if (state.selectedDocument != null &&
          !_exists(trackedDocuments, selectedDocument!.id)) {
        selectedDocument = null;
      }

      emit(DocumentsState(
        loading: false,
        documents: trackedDocuments,
        selectedDocument: selectedDocument,
        error: null,
      ));
    } catch (e) {
      emit(DocumentsState(
        loading: false,
        error: e.toString(),
        documents: const [],
        selectedDocument: null,
      ));
    }
  }

  bool _exists(List<TrackedDocument> documents, int documentId) {
    return documents.any((d) => d.id == documentId);
  }

  void select(int id) {
    if (_exists(state.documents, id)) {
      emit(state.copyWith(
        selectedDocument: state.documents.firstWhere((d) => d.id == id),
      ));
    }
  }

  @override
  Future<void> close() {
    _alive?.dispose();
    _eventStreamSubscription?.cancel();
    return super.close();
  }
}
