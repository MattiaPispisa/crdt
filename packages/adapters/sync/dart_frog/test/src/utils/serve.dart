import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';

/// Runs [handler] on a real loopback server and returns it with its ws URL.
Future<(HttpServer, Uri)> serveOnLoopback(Handler handler) async {
  final server = await serve(handler, InternetAddress.loopbackIPv4, 0);
  return (server, Uri.parse('ws://127.0.0.1:${server.port}'));
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
