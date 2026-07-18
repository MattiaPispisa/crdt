import { RoomDO } from "./room";

export { RoomDO };

interface Env {
  ROOM: DurableObjectNamespace<RoomDO>;
}

// GET /room/:id (WebSocket upgrade) -> the room's Durable Object.
export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const match = /^\/room\/([A-Za-z0-9_-]+)$/.exec(url.pathname);
    if (!match) {
      return new Response("not found", { status: 404 });
    }
    if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
      return new Response("expected websocket upgrade", { status: 426 });
    }
    const room = env.ROOM.get(env.ROOM.idFromName(match[1]));
    return room.fetch(request);
  },
} satisfies ExportedHandler<Env>;
