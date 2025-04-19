import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:crdt_lf_devtools_extension/src/application/devtools/eval.dart';
import 'package:crdt_lf_devtools_extension/src/application/devtools/event.dart';
import 'package:crdt_lf_devtools_extension/src/application/documents/documents_cubit.dart';
import 'package:devtools_app_shared/service.dart';
import 'package:equatable/equatable.dart';
import 'package:vm_service/vm_service.dart';

part 'document_changes_state.dart';

class DocumentChangesCubitArgs {
  const DocumentChangesCubitArgs({
    required this.service,
    required this.document,
  });

  final VmService service;
  final TrackedDocument document;
}

class DocumentChangesCubit extends Cubit<DocumentChangesState> {
  DocumentChangesCubit(this.args) : super(DocumentChangesState.initial()) {
    _setupEventSubscription();
  }

  final DocumentChangesCubitArgs args;

  StreamSubscription<Event>? _eventStreamSubscription;
  Disposable? _alive;

  void _setupEventSubscription() {
    _eventStreamSubscription = args.service.onExtensionEvent.listen((event) {
      if (event.isDocumentChangedEvent) {
        _loadDocumentChanges();
      }
    });
  }

  void _loadDocumentChanges() async {
    try {
      emit(DocumentChangesState(
        loading: true,
        error: null,
        descriptors: state.descriptors,
      ));

      final eval = CrdtLfEvalExtension.setup(args.service);
      final result = await eval.evalDocumentChanges(args.document, _alive);

      final descriptors = result.elements!.cast<InstanceRef>().map((element) {
        return DocumentChangeDescriptor(
            description: element.valueAsString ?? '');
      }).toList();

      emit(DocumentChangesState(
        descriptors: descriptors,
        error: null,
        loading: false,
      ));
    } catch (e) {
      emit(DocumentChangesState(
        descriptors: state.descriptors,
        error: e.toString(),
        loading: false,
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
