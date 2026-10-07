import 'dart:convert';

import 'package:serverpod/serverpod.dart';

class _TestProtocol extends DatabaseSerializationManager {
  @override
  Table<int?>? getTableForType(Type t) => null;

  @override
  List<Never> getTargetTableDefinitions() => const [];
}

class _NoEndpoints extends EndpointDispatch {
  @override
  void initializeEndpoints(Server server) {}
}

ServerConfig _portZero() {
  return ServerConfig(
    port: 0,
    publicScheme: 'http',
    publicHost: 'localhost',
    publicPort: 0,
  );
}

/// Runs [route] at [path] on a real, database-less Serverpod bound to a free
/// port, and returns the pod with the route's ws URL.
Future<(Serverpod, Uri)> serveRoute(Route route, {String path = '/'}) async {
  final pod = Serverpod(
    [],
    _TestProtocol(),
    _NoEndpoints(),
    config: ServerpodConfig(apiServer: _portZero(), webServer: _portZero()),
  );
  pod.webServer.addRoute(route, path);
  await pod.start();
  return (pod, Uri.parse('ws://127.0.0.1:${pod.webServer.port}$path'));
}

/// Stops a pod started by [serveRoute].
Future<void> stopPod(Serverpod pod) {
  return pod.shutdown(exitProcess: false);
}

/// A [Route] that answers every call with [result].
class ResultRoute extends Route {
  ResultRoute(this.result);

  final Result Function() result;

  @override
  Result handleCall(Session session, Request request) => result();
}

/// Gives the socket a few turns to carry a frame both ways.
Future<void> settle() {
  return Future<void>.delayed(const Duration(milliseconds: 100));
}

/// The bytes of a WebSocket frame, whichever kind the peer sent.
List<int> bytesOf(dynamic frame) {
  if (frame is String) {
    return utf8.encode(frame);
  }
  return frame as List<int>;
}
