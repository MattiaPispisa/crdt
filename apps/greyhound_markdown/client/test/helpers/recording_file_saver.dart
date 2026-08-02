import 'dart:typed_data';

import 'package:greyhound_markdown_client/src/services/file_saver/file_saver.dart';

/// A [FileSaver] that keeps what it was handed instead of writing it anywhere.
class RecordingFileSaver extends FileSaver {
  /// Creates a recording saver.
  RecordingFileSaver();

  /// Name of the last saved file.
  String? fileName;

  /// Bytes of the last saved file.
  Uint8List? bytes;

  /// Media type of the last saved file.
  String? mimeType;

  /// How many files were saved.
  int saves = 0;

  /// Set to `true` to act like a user who closed the save dialog.
  bool cancel = false;

  @override
  Future<bool> save({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    if (cancel) {
      return false;
    }
    this.fileName = fileName;
    this.bytes = bytes;
    this.mimeType = mimeType;
    saves++;
    return true;
  }
}
