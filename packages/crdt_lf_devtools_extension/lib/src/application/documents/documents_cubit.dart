import 'dart:async';
import 'dart:convert';

import 'package:bloc/bloc.dart';
import 'package:crdt_lf_devtools_extension/src/application/devtools/eval.dart';
import 'package:crdt_lf_devtools_extension/src/application/devtools/event.dart';
import 'package:devtools_app_shared/service.dart';
import 'package:equatable/equatable.dart';
import 'package:vm_service/vm_service.dart';

part 'documents_state.dart';

class DocumentsCubitArgs {
  const DocumentsCubitArgs({required this.service});

  final VmService service;
}

/// Cubit loading the list of CRDT documents tracked by the target app.
///
/// Refreshes whenever a new document is registered on the target side
/// (event `crdt_lf:documents:created`) or when [load] is invoked manually.
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
      } else if (event.isDocumentChangedEvent) {
        // If the event references a document not yet in our list, the
        // `crdt_lf:documents:created` event was missed (e.g. the extension
        // connected after the document was created). Reload to pick it up.
        final docs = state.documents;
        if (docs != null && !docs.any((d) => d.id == event.documentId)) {
          load();
        }
      }
    });
  }

  Future<void> load() async {
    if (state.loading) {
      return;
    }

    emit(state.copyWith(loading: true, error: null));

    try {
      _alive?.dispose();
      _alive = Disposable();

      final eval = CrdtLfEvalExtension.setup(args.service);
      final json = await eval.evalDocumentsJson(_alive);
      final list = (jsonDecode(json) as List<dynamic>)
          .map((e) => TrackedDocument.fromJson(e as Map<String, dynamic>))
          .toList();

      // Preserve selection across reloads when possible.
      TrackedDocument? selected = state.selectedDocument;
      if (selected != null) {
        selected = list.cast<TrackedDocument?>().firstWhere(
              (d) => d?.id == selected!.id,
              orElse: () => null,
            );
      }

      emit(
        DocumentsState(
          loading: false,
          documents: list,
          selectedDocument: selected,
          error: null,
        ),
      );
    } catch (e) {
      emit(
        DocumentsState(
          loading: false,
          documents: state.documents,
          selectedDocument: state.selectedDocument,
          error: e.toString(),
        ),
      );
    }
  }

  void select(int? id) {
    if (id == null) {
      emit(
        DocumentsState(
          documents: state.documents,
          selectedDocument: null,
          loading: state.loading,
          error: state.error,
        ),
      );
      return;
    }

    final docs = state.documents;
    if (docs == null) return;
    final match = docs.cast<TrackedDocument?>().firstWhere(
          (d) => d?.id == id,
          orElse: () => null,
        );
    if (match != null) {
      emit(state.copyWith(selectedDocument: match));
    }
  }

  @override
  Future<void> close() {
    _alive?.dispose();
    _eventStreamSubscription?.cancel();
    return super.close();
  }
}
