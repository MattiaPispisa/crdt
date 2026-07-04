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
}
