/// The single fugue text handler shared by every client of a room.
/// Must be identical across peers for the Fugue merge to converge.
const String kHandlerId = 'content';

/// WebSocket endpoint of the signaling server.
///
/// Override at build time with
/// `--dart-define=GREYHOUND_WS=wss://your-worker.example.com`.
const String kServerUrl = String.fromEnvironment(
  'GREYHOUND_WS',
  defaultValue: 'ws://localhost:8787',
);
