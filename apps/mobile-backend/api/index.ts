import type { IncomingMessage, ServerResponse } from "node:http"
import { createApp } from "../dist/app.js"
import { connectDb } from "../dist/config/db.js"

// Serverless entry point for Vercel. Deliberately imports only createApp()
// (pure Express wiring, zero DB/Redis/socket/queue side effects at import
// time — see src/app.ts) — never src/server.ts, whose main() starts
// Socket.IO, Mongo change-stream watchers, and BullMQ workers, none of
// which can run inside a request-scoped serverless function. Real-time
// notifications, FCM push, and the visitor escalation ladder do not work
// through this entry point; only plain REST request/response does.

const app = createApp()

// Cached across warm invocations of the same function instance so a
// re-connect isn't attempted on every request.
let dbReady: Promise<void> | null = null

export default async function handler(req: IncomingMessage, res: ServerResponse) {
  if (!dbReady) dbReady = connectDb()
  await dbReady
  app(req as never, res as never)
}
