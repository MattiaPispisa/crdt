import 'package:serverpod/serverpod.dart';

// A real project passes its generated `Protocol()` and `Endpoints()` instead.

/// A serialization manager with no models and no database tables.
class EmptyProtocol extends DatabaseSerializationManager {
  @override
  Table<int?>? getTableForType(Type t) => null;

  @override
  List<Never> getTargetTableDefinitions() => const [];
}

/// An endpoint dispatch with no endpoints: the example serves only a route.
class NoEndpoints extends EndpointDispatch {
  @override
  void initializeEndpoints(Server server) {}
}
