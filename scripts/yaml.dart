import 'dart:io' as io;
import 'package:yaml/yaml.dart' as yaml;

class YamlReader {
  YamlReader(this._pubspec);
  final io.File _pubspec;
  yaml.YamlMap? _map;

  yaml.YamlMap _getMap() {
    if (_map == null) {
      initSync();
    }
    return _map!;
  }

  void initSync() {
    _map = yaml.loadYaml(_pubspec.readAsStringSync()) as yaml.YamlMap;
  }

  String version(String package) {
    return ((_getMap()['packages'] as yaml.YamlMap)[package]
        as yaml.YamlMap)['version'] as String;
  }

  /// Reads a top-level string [key] (e.g. `name` or `version` of a package
  /// `pubspec.yaml`).
  String string(String key) => _getMap()[key] as String;

  /// Reads a top-level string [key], or `null` when the key is absent.
  String? stringOrNull(String key) => _getMap()[key] as String?;
}
