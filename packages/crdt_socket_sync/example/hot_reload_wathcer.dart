// ignore_for_file: avoid_print just for example

import 'dart:async';
import 'dart:io';

/// Hot reload watcher that monitors file changes and triggers callbacks
class HotReloadWatcher {
  /// Creates a new [HotReloadWatcher]
  HotReloadWatcher({
    required this.watchPaths,
    this.debounceDelay = const Duration(milliseconds: 500),
    this.extensions = const ['.dart'],
  });

  /// Paths to watch for changes
  final List<String> watchPaths;

  /// Delay before triggering the callback to debounce rapid changes
  final Duration debounceDelay;

  /// File extensions to watch
  final List<String> extensions;

  /// Callback to invoke when files change
  void Function()? onFileChanged;

  /// Stream subscriptions for file watchers
  final List<StreamSubscription<FileSystemEvent>> _subscriptions = [];

  /// Timer for debouncing
  Timer? _debounceTimer;

  /// Whether the watcher is currently active
  bool _isWatching = false;

  /// Start watching for file changes
  Future<void> startWatching() async {
    if (_isWatching) {
      return;
    }

    _isWatching = true;

    for (final path in watchPaths) {
      final directory = Directory(path);
      if (directory.existsSync()) {
        await _watchDirectory(directory);
      } else {
        print('⚠️  Warning: Directory does not exist: $path');
        print('   Absolute path: ${directory.absolute.path}');
      }
    }

    print('👀 Hot reload watcher started for ${watchPaths.length} path(s)');
  }

  /// Stop watching for file changes
  Future<void> stopWatching() async {
    if (!_isWatching) {
      return;
    }

    _isWatching = false;

    // Cancel all subscriptions
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();

    // Cancel debounce timer
    _debounceTimer?.cancel();
    _debounceTimer = null;

    print('🛑 Hot reload watcher stopped');
  }

  /// Watch a specific directory for changes
  Future<void> _watchDirectory(Directory directory) async {
    print('📡 Watching: ${directory.absolute.path}');

    // Watch the directory itself
    final subscription = directory.watch(recursive: true).listen(
      _handleFileEvent,
      onError: (dynamic error) {
        print('❌ Error watching directory ${directory.path}: $error');
      },
    );

    _subscriptions.add(subscription);
  }

  /// Handle a file system event
  void _handleFileEvent(FileSystemEvent event) {
    // Check if the file has a relevant extension
    final path = event.path;
    final hasRelevantExtension = extensions.any(
      (ext) => path.toLowerCase().endsWith(ext.toLowerCase()),
    );

    if (!hasRelevantExtension) {
      return;
    }

    // Skip certain files/directories
    if (_shouldSkipPath(path)) {
      return;
    }

    print('📝 File changed: ${_getRelativePath(path)}');

    // Debounce the callback to avoid multiple rapid triggers
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounceDelay, () {
      onFileChanged?.call();
    });
  }

  /// Check if a path should be skipped
  bool _shouldSkipPath(String path) {
    final fileName = path.split(Platform.pathSeparator).last;

    // Skip hidden files
    if (fileName.startsWith('.')) {
      return true;
    }

    // Skip generated files
    if (fileName.endsWith('.g.dart') || fileName.endsWith('.freezed.dart')) {
      return true;
    }

    // Skip build directories
    if (path.contains(
          '${Platform.pathSeparator}build${Platform.pathSeparator}',
        ) ||
        path.contains(
          '${Platform.pathSeparator}.dart_tool${Platform.pathSeparator}',
        )) {
      return true;
    }

    return false;
  }

  /// Get a relative path for display purposes
  String _getRelativePath(String fullPath) {
    for (final watchPath in watchPaths) {
      if (fullPath.startsWith(watchPath)) {
        return fullPath.substring(watchPath.length + 1);
      }
    }
    return fullPath;
  }

  /// Dispose of the watcher
  Future<void> dispose() async {
    await stopWatching();
  }
}
