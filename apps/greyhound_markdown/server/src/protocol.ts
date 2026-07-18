// Wire protocol shared with the Dart client
// (client/lib/src/model/protocol.dart). JSON text frames; CRDT binary blobs
// (crdt_lf Change/Snapshot bytes) travel as base64 strings and are opaque to
// the server.

export const MessageType = {
  /** S→C, on connect: stored snapshot + change log + current peers. */
  welcome: "welcome",
  /** C→S: local changes to persist and rebroadcast. */
  push: "push",
  /** S→C: persistence confirmed up to `seq`. */
  ack: "ack",
  /** S→C: changes rebroadcast from another client. */
  change: "change",
  /** C→S: compacted snapshot replacing the log up to `upto`. */
  snapshot: "snapshot",
  /** C↔S: ephemeral presence state (never persisted). */
  awareness: "awareness",
  /** S→C: a client disconnected. */
  peerLeft: "peer_left",
} as const;

export type AwarenessState = Record<string, unknown>;

export interface WelcomeMessage {
  type: typeof MessageType.welcome;
  snapshot: string | null;
  changes: string[];
  seq: number;
  logLen: number;
  peers: Record<string, AwarenessState>;
  compact: boolean;
}

export interface PushMessage {
  type: typeof MessageType.push;
  changes: string[];
}

export interface AckMessage {
  type: typeof MessageType.ack;
  seq: number;
  logLen: number;
  compact: boolean;
}

export interface ChangeMessage {
  type: typeof MessageType.change;
  from: string;
  changes: string[];
}

export interface SnapshotMessage {
  type: typeof MessageType.snapshot;
  snapshot: string;
  upto: number;
}

export interface AwarenessMessage {
  type: typeof MessageType.awareness;
  from?: string;
  state: AwarenessState;
}

export interface PeerLeftMessage {
  type: typeof MessageType.peerLeft;
  clientId: string;
}

export type ClientMessage = PushMessage | SnapshotMessage | AwarenessMessage;
