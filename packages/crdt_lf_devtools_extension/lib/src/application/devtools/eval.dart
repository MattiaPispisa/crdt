import 'package:crdt_lf_devtools_extension/src/application/documents/documents_cubit.dart';
import 'package:devtools_app_shared/service.dart';
import 'package:vm_service/vm_service.dart';
import 'package:devtools_extensions/devtools_extensions.dart' as devtools;

extension CrdtLfEvalExtension on EvalOnDartLibrary {
  /// Setup the [EvalOnDartLibrary] for the CRDT LF extension
  static EvalOnDartLibrary setup(VmService service) {
    return EvalOnDartLibrary(
      'package:crdt_lf/src/devtools/devtools.dart',
      service,
      serviceManager: devtools.serviceManager,
    );
  }

  /// `TrackedDocument.all`
  ///
  /// Returns a list of all tracked documents.
  Future<Instance> evalDocuments(Disposable? isAlive) async {
    return evalInstance(
      'TrackedDocument.all',
      isAlive: isAlive,
    );
  }

  /// `describeChanges(document)`
  ///
  /// Returns a string describing the changes to the document.
  Future<Instance> evalDocumentChanges(
    TrackedDocument document,
    Disposable? isAlive,
  ) async {
    return evalInstance(
      'describeChanges(document)',
      isAlive: isAlive,
      scope: {
        'document': document.document.id!,
      },
    );
  }
}
