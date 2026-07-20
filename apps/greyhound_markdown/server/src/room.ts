import { DurableObject } from "cloudflare:workers";
import {
  AwarenessStateMessage,
  AwarenessUpdateMessage,
  ClientAwareness,
  ClientMessage,
  MessageType,
  PingMessage,
  RelayAckMessage,
  RelayChangesMessage,
  RelayHelloMessage,
  RelayPushMessage,
  RelaySnapshotUploadMessage,
  RelayWelcomeMessage,
} from "./protocol";

// Storage layout:
//   meta        -> { seq, snapChunks }   (last assigned seq, snapshot chunk count)
//   snap:<i>    -> base64 snapshot chunk i (0..snapChunks-1)
//   log:<seq>   -> base64 change blob, key zero-padded so list() sorts by seq
//
// The DO is a relay server (crdt_socket_sync relay protocol): blobs are
// opaque crdt_lf binary; all CRDT merge happens in the clients. Compaction:
// when the log grows past LOG_COMPACT_LEN one client is asked
// (compact: true on ack/welcome) to upload a snapshot, which replaces the
// log prefix.
//
// Sessions: the DO assigns a sessionId per connection and hands it to the
// client in the welcome. A connection becomes part of the room only after
// its hello (`joined`). Awareness (presence) lives on the socket
// attachments, never in storage.

interface Meta {
  seq: number;
  snapChunks: number;
}

interface Attachment {
  sessionId: string;
  joined: boolean;
  documentId: string | null;
  metadata: Record<string, unknown> | null;
}

const LOG_COMPACT_LEN = 200;
const COMPACT_RETRY_MS = 30_000;
// DO storage values are capped at 128KiB; keep chunks well under it.
const SNAP_CHUNK_SIZE = 100_000;
const SEQ_PAD = 10;

const logKey = (seq: number) => `log:${String(seq).padStart(SEQ_PAD, "0")}`;

export class RoomDO extends DurableObject {
  private compactAskedAt = 0;

  override async fetch(request: Request): Promise<Response> {
    if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
      return new Response("expected websocket", { status: 426 });
    }
    const pair = new WebSocketPair();
    const [client, server] = [pair[0], pair[1]];
    this.ctx.acceptWebSocket(server);
    server.serializeAttachment({
      sessionId: crypto.randomUUID(),
      joined: false,
      documentId: null,
      metadata: null,
    } satisfies Attachment);
    // No welcome yet: the room state is served in reply to the hello.
    return new Response(null, { status: 101, webSocket: client });
  }

  override async webSocketMessage(
    ws: WebSocket,
    raw: string | ArrayBuffer,
  ): Promise<void> {
    // The Dart relay client sends binary frames (UTF-8 JSON).
    const text = typeof raw === "string" ? raw : new TextDecoder().decode(raw);
    let msg: ClientMessage;
    try {
      msg = JSON.parse(text) as ClientMessage;
    } catch {
      return;
    }
    switch (msg.type) {
      case MessageType.relayHello:
        await this.handleHello(ws, msg);
        break;
      case MessageType.relayPush:
        await this.handlePush(ws, msg);
        break;
      case MessageType.relaySnapshotUpload:
        await this.handleSnapshotUpload(ws, msg);
        break;
      case MessageType.relayStateRequest:
        await this.handleStateRequest(ws, msg.documentId);
        break;
      case MessageType.ping:
        this.handlePing(ws, msg);
        break;
      case MessageType.awarenessUpdate:
        this.handleAwarenessUpdate(ws, msg);
        break;
      case MessageType.awarenessQuery:
        this.handleAwarenessQuery(ws, msg.documentId);
        break;
    }
  }

  override async webSocketClose(ws: WebSocket): Promise<void> {
    this.broadcastAwarenessState(ws);
  }

  override async webSocketError(ws: WebSocket): Promise<void> {
    this.broadcastAwarenessState(ws);
  }

  /// Join: adopt the room documentId, announce the presence and serve the
  /// persisted room state as a welcome.
  private async handleHello(
    ws: WebSocket,
    msg: RelayHelloMessage,
  ): Promise<void> {
    const att = attachment(ws);
    if (!att) return;
    const joined: Attachment = {
      ...att,
      joined: true,
      documentId: msg.documentId,
      metadata: {},
    };
    ws.serializeAttachment(joined);

    // Awareness join semantics (mirrors ServerAwarenessPlugin):
    // announce the joiner to the others, send the full state to the joiner.
    const update: AwarenessUpdateMessage = {
      type: MessageType.awarenessUpdate,
      documentId: msg.documentId,
      state: { clientId: joined.sessionId, metadata: {} },
    };
    this.broadcast(JSON.stringify(update), ws);
    this.sendAwarenessState(ws, msg.documentId);

    await this.sendWelcome(ws, joined);
  }

  /// Re-sync request from an already joined client.
  private async handleStateRequest(
    ws: WebSocket,
    documentId: string,
  ): Promise<void> {
    const att = this.joinedAttachment(ws, documentId);
    if (!att) return;
    await this.sendWelcome(ws, att);
  }

  private async sendWelcome(ws: WebSocket, att: Attachment): Promise<void> {
    const meta = await this.getMeta();
    const snapshot = await this.readSnapshot(meta);
    const log = await this.ctx.storage.list<string>({ prefix: "log:" });
    const welcome: RelayWelcomeMessage = {
      type: MessageType.relayWelcome,
      documentId: att.documentId ?? "",
      sessionId: att.sessionId,
      snapshot,
      changes: [...log.values()],
      seq: meta.seq,
      logLength: log.size,
      compact: this.shouldCompact(log.size),
    };
    ws.send(JSON.stringify(welcome));
  }

  private async handlePush(
    ws: WebSocket,
    msg: RelayPushMessage,
  ): Promise<void> {
    const att = this.joinedAttachment(ws, msg.documentId);
    if (!att) return;
    const changes = msg.changes;
    if (!Array.isArray(changes) || changes.length === 0) return;
    const meta = await this.getMeta();
    const entries: Record<string, string> = {};
    for (const blob of changes) {
      meta.seq += 1;
      entries[logKey(meta.seq)] = blob;
    }
    await this.ctx.storage.put(entries);
    await this.ctx.storage.put("meta", meta);
    const logLength = (await this.ctx.storage.list({ prefix: "log:" })).size;
    const rebroadcast: RelayChangesMessage = {
      type: MessageType.relayChanges,
      documentId: msg.documentId,
      changes,
      seq: meta.seq,
      from: att.sessionId,
    };
    this.broadcast(JSON.stringify(rebroadcast), ws);
    const ack: RelayAckMessage = {
      type: MessageType.relayAck,
      documentId: msg.documentId,
      seq: meta.seq,
      count: changes.length,
      logLength,
      compact: this.shouldCompact(logLength),
    };
    ws.send(JSON.stringify(ack));
  }

  private async handleSnapshotUpload(
    ws: WebSocket,
    msg: RelaySnapshotUploadMessage,
  ): Promise<void> {
    if (!this.joinedAttachment(ws, msg.documentId)) return;
    const snapshot = msg.snapshot;
    const upToSeq = msg.upToSeq;
    if (typeof snapshot !== "string" || typeof upToSeq !== "number") return;
    const meta = await this.getMeta();
    const chunks: Record<string, string> = {};
    let count = 0;
    for (let i = 0; i < snapshot.length; i += SNAP_CHUNK_SIZE) {
      chunks[`snap:${count}`] = snapshot.slice(i, i + SNAP_CHUNK_SIZE);
      count += 1;
    }
    await this.ctx.storage.put(chunks);
    for (let i = count; i < meta.snapChunks; i += 1) {
      await this.ctx.storage.delete(`snap:${i}`);
    }
    meta.snapChunks = count;
    await this.ctx.storage.put("meta", meta);
    const log = await this.ctx.storage.list({ prefix: "log:" });
    const stale = [...log.keys()].filter((k) => k <= logKey(upToSeq));
    // storage.delete accepts at most 128 keys per call.
    for (let i = 0; i < stale.length; i += 128) {
      await this.ctx.storage.delete(stale.slice(i, i + 128));
    }
    this.compactAskedAt = 0;
  }

  /// The client detects half-open connections through pongs: always reply.
  private handlePing(ws: WebSocket, msg: PingMessage): void {
    ws.send(
      JSON.stringify({
        type: MessageType.pong,
        documentId: msg.documentId,
        originalTimestamp: msg.timestamp,
        responseTimestamp: Date.now(),
      }),
    );
  }

  private handleAwarenessUpdate(
    ws: WebSocket,
    msg: AwarenessUpdateMessage,
  ): void {
    const att = this.joinedAttachment(ws, msg.documentId);
    if (!att) return;
    ws.serializeAttachment({
      ...att,
      metadata: msg.state.metadata ?? {},
    } satisfies Attachment);
    this.broadcast(JSON.stringify(msg), ws);
  }

  private handleAwarenessQuery(ws: WebSocket, documentId: string): void {
    if (!this.joinedAttachment(ws, documentId)) return;
    this.sendAwarenessState(ws, documentId);
  }

  /// Send the full presence state to [ws].
  private sendAwarenessState(ws: WebSocket, documentId: string): void {
    const msg: AwarenessStateMessage = {
      type: MessageType.awarenessState,
      documentId,
      awareness: { documentId, states: this.awarenessStates() },
    };
    try {
      ws.send(JSON.stringify(msg));
    } catch {
      // Socket already gone; close events will clean up.
    }
  }

  /// A client left: broadcast the remaining full presence state
  /// (mirrors ServerAwarenessPlugin.onSessionClosed).
  private broadcastAwarenessState(closed: WebSocket): void {
    const att = attachment(closed);
    if (!att?.joined || att.documentId === null) return;
    const msg: AwarenessStateMessage = {
      type: MessageType.awarenessState,
      documentId: att.documentId,
      awareness: {
        documentId: att.documentId,
        states: this.awarenessStates(closed),
      },
    };
    this.broadcast(JSON.stringify(msg), closed);
  }

  /// The presence entries of every joined socket (except [except]).
  private awarenessStates(except?: WebSocket): Record<string, ClientAwareness> {
    const states: Record<string, ClientAwareness> = {};
    for (const socket of this.ctx.getWebSockets()) {
      if (socket === except) continue;
      const att = attachment(socket);
      if (att?.joined) {
        states[att.sessionId] = {
          clientId: att.sessionId,
          metadata: att.metadata ?? {},
        };
      }
    }
    return states;
  }

  /// The attachment of [ws], only if it joined [documentId].
  private joinedAttachment(
    ws: WebSocket,
    documentId: string,
  ): Attachment | null {
    const att = attachment(ws);
    if (!att?.joined || att.documentId !== documentId) return null;
    return att;
  }

  /// Send [frame] to every joined socket except [except].
  private broadcast(frame: string, except: WebSocket): void {
    for (const socket of this.ctx.getWebSockets()) {
      if (socket === except) continue;
      if (!attachment(socket)?.joined) continue;
      try {
        socket.send(frame);
      } catch {
        // Socket already gone; close events will clean up.
      }
    }
  }

  private shouldCompact(logLength: number): boolean {
    if (logLength <= LOG_COMPACT_LEN) return false;
    const now = Date.now();
    if (now - this.compactAskedAt < COMPACT_RETRY_MS) return false;
    this.compactAskedAt = now;
    return true;
  }

  private async getMeta(): Promise<Meta> {
    return (
      (await this.ctx.storage.get<Meta>("meta")) ?? { seq: 0, snapChunks: 0 }
    );
  }

  private async readSnapshot(meta: Meta): Promise<string | null> {
    if (meta.snapChunks === 0) return null;
    const keys = Array.from({ length: meta.snapChunks }, (_, i) => `snap:${i}`);
    const chunks = await this.ctx.storage.get<string>(keys);
    return keys.map((k) => chunks.get(k) ?? "").join("");
  }
}

function attachment(ws: WebSocket): Attachment | null {
  try {
    return ws.deserializeAttachment() as Attachment;
  } catch {
    return null;
  }
}
