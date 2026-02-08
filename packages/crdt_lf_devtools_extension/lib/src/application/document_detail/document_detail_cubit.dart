import 'dart:async';
import 'dart:convert';

import 'package:bloc/bloc.dart';
import 'package:crdt_lf_devtools_extension/src/application/devtools/eval.dart';
import 'package:crdt_lf_devtools_extension/src/application/devtools/event.dart';
import 'package:crdt_lf_devtools_extension/src/application/documents/documents_cubit.dart';
import 'package:devtools_app_shared/service.dart' as devtools;
import 'package:equatable/equatable.dart';
import 'package:vm_service/vm_service.dart' as vm_service;

part 'document_detail_state.dart';

class DocumentDetailCubitArgs {
  const DocumentDetailCubitArgs({
    required this.service,
    required this.document,
  });

  final vm_service.VmService service;
  final TrackedDocument document;
}

/// Cubit loading the full state of a single document, including handler list.
///
/// Reloads when the target emits `crdt_lf:document:changed` for
/// [args.document], so each newly applied change refreshes the visible state.
class DocumentDetailCubit extends Cubit<DocumentDetailState> {
  DocumentDetailCubit(this.args) : super(DocumentDetailState.initial()) {
    _load();
    _setupEventSubscription();
  }

  final DocumentDetailCubitArgs args;

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
      final json = await eval.evalDocumentJson(args.document.id, _alive);
      final map = jsonDecode(json) as Map<String, dynamic>;

      if (map.containsKey('error')) {
        throw StateError(map['error'] as String);
      }

      final handlers = (map['handlers'] as List<dynamic>)
          .map((h) => HandlerSummary.fromJson(h as Map<String, dynamic>))
          .toList();

      emit(
        DocumentDetailState(
          loading: false,
          error: null,
          document: TrackedDocument.fromJson(map),
          handlers: handlers,
        ),
      );
    } catch (e) {
      emit(state.copyWith(loading: false, error: e.toString()));
    }
  }

  @override
  Future<void> close() {
    _alive?.dispose();
    _eventStreamSubscription?.cancel();
    return super.close();
  }
}
