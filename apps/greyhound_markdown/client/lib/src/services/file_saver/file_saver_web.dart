import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'package:greyhound_markdown_client/src/services/file_saver/file_saver.dart';

/// `window.showSaveFilePicker`, from the File System Access API.
///
/// Declared here because `package:web` does not cover it. Only called once
/// [_canPickLocation] says the browser has it.
@JS('window.showSaveFilePicker')
external JSPromise<web.FileSystemFileHandle> _showSaveFilePicker(
  JSObject options,
);

/// Whether the browser lets the user choose where the file goes.
///
/// True on Chrome and Edge; false on Firefox and Safari, which have no File
/// System Access API.
bool get _canPickLocation => globalContext.has('showSaveFilePicker');

/// Saves a file through the browser.
///
/// Where it can, it opens the operating system's save dialog, so the user
/// picks the folder and confirms the name. Firefox and Safari have no such
/// dialog: there the file goes to the downloads folder, under the name the
/// app asked for.
class PlatformFileSaver extends FileSaver {
  /// Create a web file saver.
  const PlatformFileSaver();

  @override
  Future<bool> save({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    if (_canPickLocation) {
      return _pickAndWrite(
        fileName: fileName,
        bytes: bytes,
        mimeType: mimeType,
      );
    }
    _download(fileName: fileName, bytes: bytes, mimeType: mimeType);
    return true;
  }

  /// Opens the system save dialog and writes the file where the user chose.
  ///
  /// Returns `false` when they dismissed it: the browser reports that as an
  /// `AbortError`, which is a choice and not a failure.
  Future<bool> _pickAndWrite({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    final dot = fileName.lastIndexOf('.');
    final extension = dot < 0 ? '' : fileName.substring(dot);
    final options =
        {
              'suggestedName': fileName,
              'types': [
                {
                  'description': '$extension file',
                  'accept': {
                    mimeType: [extension],
                  },
                },
              ],
            }.jsify()!
            as JSObject;

    final web.FileSystemFileHandle handle;
    try {
      handle = await _showSaveFilePicker(options).toDart;
    } on Object catch (error) {
      if (_isAbort(error)) {
        return false;
      }
      rethrow;
    }
    final writable = await handle.createWritable().toDart;
    await writable.write(bytes.toJS).toDart;
    await writable.close().toDart;
    return true;
  }

  /// Sends the bytes to the downloads folder.
  ///
  /// A `Blob` behind a temporary object URL, pulled by a hidden anchor. The
  /// URL is released right after — it would otherwise pin the blob in memory
  /// for the whole session.
  void _download({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) {
    final blob = web.Blob(
      <JSAny>[bytes.toJS].toJS,
      web.BlobPropertyBag(type: mimeType),
    );
    final url = web.URL.createObjectURL(blob);
    final anchor =
        web.document.createElement('a') as web.HTMLAnchorElement
          ..href = url
          ..download = fileName
          ..style.display = 'none';
    web.document.body!.appendChild(anchor);
    anchor.click();
    anchor.remove();
    web.URL.revokeObjectURL(url);
  }
}

/// Whether [error] is the browser saying the user closed the save dialog.
///
/// Matched on the text rather than on the type: a `DOMException` crossing
/// from JS has no type test that holds on both dart2js and wasm (the analyzer
/// rejects `is DOMException` for exactly that reason).
bool _isAbort(Object error) => error.toString().contains('AbortError');
