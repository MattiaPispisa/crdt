import { RoomDO } from "./room";

export { RoomDO };

interface Env {
  ROOM: DurableObjectNamespace<RoomDO>;
  ALLOWED_ORIGINS?: string;
}

// Browsers always attach an Origin header to WebSocket upgrades and other
// sites cannot forge it, so an allowlist blocks cross-site browser abuse.
// Requests without an Origin (curl, native clients, tests) pass through:
// Origin is not trustworthy outside the browser anyway, so rejecting them
// would only break tooling without adding real protection.
function originAllowed(request: Request, env: Env): boolean {
  const origin = request.headers.get("Origin");
  if (!origin) return true;
  let hostname: string;
  try {
    hostname = new URL(origin).hostname;
  } catch {
    return false;
  }
  if (hostname === "localhost" || hostname === "127.0.0.1") return true;
  const allowed = (env.ALLOWED_ORIGINS ?? "")
    .split(",")
    .map((o) => o.trim())
    .filter((o) => o.length > 0);
  return allowed.includes(origin);
}

// GET /room/:id (WebSocket upgrade) -> the room's Durable Object.
export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const match = /^\/room\/([A-Za-z0-9_-]+)$/.exec(url.pathname);
    if (!match) {
      return new Response("not found", { status: 404 });
    }
    if (!originAllowed(request, env)) {
      return new Response("origin not allowed", { status: 403 });
    }
    if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
      return new Response("expected websocket upgrade", { status: 426 });
    }
    const room = env.ROOM.get(env.ROOM.idFromName(match[1]));
    return room.fetch(request);
  },
} satisfies ExportedHandler<Env>;
