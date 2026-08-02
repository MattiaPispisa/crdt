import 'dart:typed_data';

import 'package:greyhound_markdown_client/src/services/file_saver/file_saver_web.dart'
    if (dart.library.io) 'package:greyhound_markdown_client/src/services/file_saver/file_saver_io.dart'
    as platform;

/// Hands a generated file to the user.
///
/// One implementation per platform: the web one asks where to put the file
/// when the browser can, the native one writes it to a folder. Tests pass
/// their own instead of touching the disk.
abstract class FileSaver {
  /// Allows subclasses to be const.
  const FileSaver();

  /// The saver of the platform the app runs on.
  factory FileSaver.forPlatform() = platform.PlatformFileSaver;

  /// Saves [bytes] as [fileName], a file of type [mimeType].
  ///
  /// Returns `false` when the user closed the save dialog without picking a
  /// destination: nothing was written, and nothing went wrong.
  Future<bool> save({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  });
}
