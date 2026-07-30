import 'package:hydrated_bloc/hydrated_bloc.dart';

/// Hydrated storage backed by a plain map.
///
/// Passed to a cubit as `storage:` so tests never touch the real box — and
/// never touch the global `HydratedBloc.storage` either, so they stay
/// independent of each other.
class MemoryStorage implements Storage {
  /// Starts empty, or already holding [seed] — a previous session's payloads
  /// keyed by storage token.
  MemoryStorage([Map<String, dynamic>? seed]) : _values = {...?seed};

  final Map<String, dynamic> _values;

  @override
  dynamic read(String key) => _values[key];

  @override
  Future<void> write(String key, dynamic value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<void> clear() async => _values.clear();

  @override
  Future<void> close() async {}
}
