import 'package:devtools_app_shared/service.dart';
import 'package:vm_service/vm_service.dart';
import 'package:devtools_extensions/devtools_extensions.dart' as devtools;

/// Helpers around [EvalOnDartLibrary] for the CRDT LF devtools extension.
///
/// All endpoints below return a JSON string that the extension decodes locally.
/// Keeping the wire format as plain JSON avoids the cost of walking nested
/// [Instance] graphs across the VM service.
extension CrdtLfEvalExtension on EvalOnDartLibrary {
  /// Build an [EvalOnDartLibrary] anchored on `crdt_lf`'s devtools entrypoint.
  static EvalOnDartLibrary setup(VmService service) {
    return EvalOnDartLibrary(
      'package:crdt_lf/src/devtools/devtools.dart',
      service,
      serviceManager: devtools.serviceManager,
    );
  }

  /// Evaluates [expression] and returns the inner string value.
  ///
  /// The target functions return a `String` containing JSON; this helper
  /// stitches together `eval` + `retrieveFullStringValue` so callers can pass
  /// the raw decoded JSON straight to `jsonDecode`.
  Future<String> evalJsonString(
    String expression, {
    required Disposable? isAlive,
    Map<String, String>? scope,
  }) async {
    final instance = await evalInstance(
      expression,
      isAlive: isAlive,
      scope: scope,
    );
    final value = await service.retrieveFullStringValue(
      isolateRef!.id!,
      instance,
    );
    if (value == null) {
      throw StateError('Empty JSON response from $expression');
    }
    return value;
  }

  /// JSON array describing every tracked document (id, documentId, peerId,
  /// changesCount, handlersCount, version).
  Future<String> evalDocumentsJson(Disposable? isAlive) {
    return evalJsonString('describeDocumentsJson()', isAlive: isAlive);
  }

  /// JSON object describing a single document: metadata + handlers list.
  Future<String> evalDocumentJson(int trackedId, Disposable? isAlive) {
    return evalJsonString('describeDocumentJson($trackedId)', isAlive: isAlive);
  }

  /// JSON array describing every change of a document
  /// (id, hlc, deps, payloadSize, bytes).
  Future<String> evalDocumentChangesJson(int trackedId, Disposable? isAlive) {
    return evalJsonString('describeChangesJson($trackedId)', isAlive: isAlive);
  }

  /// JSON object describing the document timeline (length + ordered changes).
  Future<String> evalDocumentHistoryJson(int trackedId, Disposable? isAlive) {
    return evalJsonString('describeHistoryJson($trackedId)', isAlive: isAlive);
  }
}
