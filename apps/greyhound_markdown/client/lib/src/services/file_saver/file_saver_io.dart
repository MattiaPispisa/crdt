import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'package:greyhound_markdown_client/src/services/file_saver/file_saver.dart';

/// Writes a file next to the user's other documents.
///
/// The app ships as a web build, so this exists to keep the code compiling
/// (and testable) off the browser rather than as a shipped feature. It prefers
/// the platform downloads folder and falls back to the documents one, which
/// every platform provides.
class PlatformFileSaver extends FileSaver {
  /// Create a native file saver.
  const PlatformFileSaver();

  @override
  Future<bool> save({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    final directory =
        await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    await File('${directory.path}${Platform.pathSeparator}$fileName')
        .writeAsBytes(bytes);
    return true;
  }
}
