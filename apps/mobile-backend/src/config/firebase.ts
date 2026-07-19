import admin from "firebase-admin"
import { env } from "./env.js"

const REQUIRED_SA_FIELDS = ["project_id", "private_key", "client_email"]

// Called once at boot (see server.ts). FCM is optional in dev (no env var
// set at all is fine), but if it IS set, a malformed value should fail the
// process at startup, not the first time a BullMQ job tries to send a push.
export function validateFirebaseConfig(saJson: string | undefined = env.firebaseSaJson): void {
  if (!saJson) return
  let parsed: Record<string, unknown>
  try {
    parsed = JSON.parse(saJson)
  } catch (err) {
    throw new Error(`FIREBASE_SA_JSON is not valid JSON: ${(err as Error).message}`)
  }
  const missing = REQUIRED_SA_FIELDS.filter((k) => !parsed[k])
  if (missing.length) {
    throw new Error(`FIREBASE_SA_JSON is missing required field(s): ${missing.join(", ")}`)
  }
}

let app: admin.app.App | null = null

export function firebaseApp(): admin.app.App {
  if (app) return app
  if (!env.firebaseSaJson) throw new Error("FIREBASE_SA_JSON not set")
  const credential = admin.credential.cert(JSON.parse(env.firebaseSaJson))
  app = admin.initializeApp({ credential })
  return app
}

export const messaging = (): admin.messaging.Messaging => firebaseApp().messaging()
