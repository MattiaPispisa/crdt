import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'package:greyhound_markdown_client/src/services/file_saver.dart';

/// Downloads a file through the browser.
///
/// The bytes go into a `Blob`, a temporary object URL points at it, and a
/// hidden anchor is clicked to start the download. The URL is released right
/// after — it would otherwise pin the blob in memory for the whole session.
class PlatformFileSaver extends FileSaver {
  /// Create a web file saver.
  const PlatformFileSaver();

  @override
  Future<void> save({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
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
