import { DurableObject } from "cloudflare:workers";
import {
  AckMessage,
  AwarenessState,
  ChangeMessage,
  ClientMessage,
  MessageType,
  PeerLeftMessage,
  WelcomeMessage,
} from "./protocol";

// Storage layout:
//   meta        -> { seq, snapChunks }   (last assigned seq, snapshot chunk count)
//   snap:<i>    -> base64 snapshot chunk i (0..snapChunks-1)
//   log:<seq>   -> base64 change blob, key zero-padded so list() sorts by seq
//
// The DO is a dumb relay: blobs are opaque crdt_lf binary; all CRDT merge
// happens in the clients. Compaction: when the log grows past LOG_COMPACT_LEN
// one client is asked (compact: true on ack/welcome) to upload a snapshot,
// which replaces the log prefix.

interface Meta {
  seq: number;
  snapChunks: number;
}

interface Attachment {
  clientId: string;
  awareness: AwarenessState | null;
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
    const clientId = new URL(request.url).searchParams.get("client");
    if (!clientId) {
      return new Response("missing client id", { status: 400 });
    }
    const pair = new WebSocketPair();
    const [client, server] = [pair[0], pair[1]];
    this.ctx.acceptWebSocket(server);
    server.serializeAttachment({ clientId, awareness: null } satisfies Attachment);
    await this.sendWelcome(server);
    return new Response(null, { status: 101, webSocket: client });
  }

  override async webSocketMessage(
    ws: WebSocket,
    raw: string | ArrayBuffer,
  ): Promise<void> {
    if (typeof raw !== "string") return;
    let msg: ClientMessage;
    try {
      msg = JSON.parse(raw) as ClientMessage;
    } catch {
      return;
    }
    switch (msg.type) {
      case MessageType.push:
        await this.handlePush(ws, msg.changes);
        break;
      case MessageType.snapshot:
        await this.handleSnapshot(msg.snapshot, msg.upto);
        break;
      case MessageType.awareness:
        this.handleAwareness(ws, msg.state);
        break;
    }
  }

  override async webSocketClose(ws: WebSocket): Promise<void> {
    this.broadcastPeerLeft(ws);
  }

  override async webSocketError(ws: WebSocket): Promise<void> {
    this.broadcastPeerLeft(ws);
  }

  private async sendWelcome(ws: WebSocket): Promise<void> {
    const meta = await this.getMeta();
    const snapshot = await this.readSnapshot(meta);
    const log = await this.ctx.storage.list<string>({ prefix: "log:" });
    const peers: Record<string, AwarenessState> = {};
    const self = attachment(ws);
    for (const other of this.ctx.getWebSockets()) {
      if (other === ws) continue;
      const att = attachment(other);
      if (att?.awareness && att.clientId !== self?.clientId) {
        peers[att.clientId] = att.awareness;
      }
    }
    const welcome: WelcomeMessage = {
      type: MessageType.welcome,
      snapshot,
      changes: [...log.values()],
      seq: meta.seq,
      logLen: log.size,
      peers,
      compact: this.shouldCompact(log.size),
    };
    ws.send(JSON.stringify(welcome));
  }

  private async handlePush(ws: WebSocket, changes: string[]): Promise<void> {
    if (!Array.isArray(changes) || changes.length === 0) return;
    const meta = await this.getMeta();
    const entries: Record<string, string> = {};
    for (const blob of changes) {
      meta.seq += 1;
      entries[logKey(meta.seq)] = blob;
    }
    await this.ctx.storage.put(entries);
    await this.ctx.storage.put("meta", meta);
    const logLen = (await this.ctx.storage.list({ prefix: "log:" })).size;
    const from = attachment(ws)?.clientId ?? "?";
    const change: ChangeMessage = {
      type: MessageType.change,
      from,
      changes,
    };
    this.broadcast(JSON.stringify(change), ws);
    const ack: AckMessage = {
      type: MessageType.ack,
      seq: meta.seq,
      logLen,
      compact: this.shouldCompact(logLen),
    };
    ws.send(JSON.stringify(ack));
  }

  private async handleSnapshot(snapshot: string, upto: number): Promise<void> {
    if (typeof snapshot !== "string" || typeof upto !== "number") return;
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
    const stale = [...log.keys()].filter((k) => k <= logKey(upto));
    // storage.delete accepts at most 128 keys per call.
    for (let i = 0; i < stale.length; i += 128) {
      await this.ctx.storage.delete(stale.slice(i, i + 128));
    }
    this.compactAskedAt = 0;
  }

  private handleAwareness(ws: WebSocket, state: AwarenessState): void {
    const att = attachment(ws);
    if (!att) return;
    ws.serializeAttachment({ ...att, awareness: state } satisfies Attachment);
    this.broadcast(
      JSON.stringify({ type: MessageType.awareness, from: att.clientId, state }),
      ws,
    );
  }

  private broadcastPeerLeft(ws: WebSocket): void {
    const att = attachment(ws);
    if (!att) return;
    const msg: PeerLeftMessage = {
      type: MessageType.peerLeft,
      clientId: att.clientId,
    };
    this.broadcast(JSON.stringify(msg), ws);
  }

  private broadcast(frame: string, except: WebSocket): void {
    for (const socket of this.ctx.getWebSockets()) {
      if (socket === except) continue;
      try {
        socket.send(frame);
      } catch {
        // Socket already gone; close events will clean up.
      }
    }
  }

  private shouldCompact(logLen: number): boolean {
    if (logLen <= LOG_COMPACT_LEN) return false;
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
