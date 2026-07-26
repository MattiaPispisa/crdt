// Wire protocol of crdt_socket_sync's relay mode (TypeScript reference
// implementation of the relay server contract).
//
// Keep in sync with:
//   packages/crdt_socket_sync/lib/src/relay/common/message.dart   (20-26)
//   packages/crdt_socket_sync/lib/src/common/message.dart         (ping/pong/error)
//   packages/crdt_socket_sync/lib/src/plugins/awareness/common/message.dart (100-102)
//
// Frames are JSON envelopes typed by a numeric `type` code (0-19 core,
// 20-39 relay, 100+ plugins). The Dart client sends BINARY frames (UTF-8
// JSON); replies may be text frames. CRDT payloads (crdt_lf Change/Snapshot
// bytes) travel as base64 strings and are opaque to the server: all merging
// happens in the clients.

export const MessageType = {
  /** C→S: liveness probe. The server MUST reply with a pong: the client
   * treats a missing pong within its ping timeout as a dead connection. */
  ping: 5,
  /** S→C: reply to a ping. */
  pong: 6,
  /** S→C: protocol error. */
  error: 7,
  /** C→S: join request; the server replies with a welcome. */
  relayHello: 20,
  /** S→C: join response carrying the persisted room state. */
  relayWelcome: 21,
  /** C→S: change blobs to persist and rebroadcast. */
  relayPush: 22,
  /** S→C: persistence confirmed for the last push. */
  relayAck: 23,
  /** S→C: change blobs rebroadcast from another client. */
  relayChanges: 24,
  /** C→S: compacted snapshot replacing the log up to `upToSeq`. */
  relaySnapshotUpload: 25,
  /** C→S: re-sync request; the server replies with a welcome. */
  relayStateRequest: 26,
  /** C↔S: a single client's ephemeral presence state. */
  awarenessUpdate: 100,
  /** C→S: request the full presence state. */
  awarenessQuery: 101,
  /** S→C: the full presence state of the room. */
  awarenessState: 102,
} as const;

export interface PingMessage {
  type: typeof MessageType.ping;
  documentId: string;
  timestamp: number;
  /** Reported by CRDT-aware clients; a relay ignores it. */
  versionVector?: string;
}

export interface PongMessage {
  type: typeof MessageType.pong;
  documentId: string;
  originalTimestamp: number;
  responseTimestamp: number;
}

export interface ErrorMessage {
  type: typeof MessageType.error;
  documentId: string;
  code: string;
  message: string;
}

export interface RelayHelloMessage {
  type: typeof MessageType.relayHello;
  documentId: string;
  author: string;
}

export interface RelayWelcomeMessage {
  type: typeof MessageType.relayWelcome;
  documentId: string;
  sessionId: string;
  snapshot: string | null;
  changes: string[];
  seq: number;
  logLength: number;
  compact: boolean;
}

export interface RelayPushMessage {
  type: typeof MessageType.relayPush;
  documentId: string;
  changes: string[];
}

export interface RelayAckMessage {
  type: typeof MessageType.relayAck;
  documentId: string;
  seq: number;
  count: number;
  logLength: number;
  compact: boolean;
}

export interface RelayChangesMessage {
  type: typeof MessageType.relayChanges;
  documentId: string;
  changes: string[];
  /** Last sequence assigned to `changes`: they cover
   * `(seq - changes.length, seq]`. */
  seq: number;
  from: string | null;
}

export interface RelaySnapshotUploadMessage {
  type: typeof MessageType.relaySnapshotUpload;
  documentId: string;
  snapshot: string;
  upToSeq: number;
}

export interface RelayStateRequestMessage {
  type: typeof MessageType.relayStateRequest;
  documentId: string;
}

export interface ClientAwareness {
  clientId: string;
  metadata: Record<string, unknown>;
}

export interface DocumentAwareness {
  documentId: string;
  states: Record<string, ClientAwareness>;
}

export interface AwarenessUpdateMessage {
  type: typeof MessageType.awarenessUpdate;
  documentId: string;
  state: ClientAwareness;
}

export interface AwarenessQueryMessage {
  type: typeof MessageType.awarenessQuery;
  documentId: string;
}

export interface AwarenessStateMessage {
  type: typeof MessageType.awarenessState;
  documentId: string;
  awareness: DocumentAwareness;
}

/** The message types the server accepts inbound. */
export type ClientMessage =
  | PingMessage
  | RelayHelloMessage
  | RelayPushMessage
  | RelaySnapshotUploadMessage
  | RelayStateRequestMessage
  | AwarenessUpdateMessage
  | AwarenessQueryMessage;
