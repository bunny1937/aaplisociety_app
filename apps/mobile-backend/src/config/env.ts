import "dotenv/config"

function req(name: string): string {
  const v = process.env[name]
  if (!v) throw new Error(`Missing env: ${name}`)
  return v
}

export const env = {
  port: Number(process.env.PORT ?? 5001),
  mongoUri: req("MONGODB_URI"),
  jwtSecret: req("JWT_SECRET"),
  refreshSecret: req("REFRESH_SECRET"),
  accessTtl: process.env.ACCESS_TTL ?? "15m",
  refreshTtl: process.env.REFRESH_TTL ?? "30d",
  redisUrl: req("REDIS_URL"),
  corsOrigins: (process.env.CORS_ORIGINS ?? "http://localhost:3000,https://aaplisociety.vercel.app")
    .split(",").map((s) => s.trim()).filter(Boolean),
  firebaseSaJson: process.env.FIREBASE_SA_JSON,
  brevoApiKey: req("BREVO_API_KEY"),
  brevoSenderEmail: req("BREVO_SENDER_EMAIL"),
  brevoSenderName: process.env.BREVO_SENDER_NAME ?? "AapliSocietyy",
  r2: {
    endpoint: process.env.R2_ENDPOINT,
    bucket: process.env.R2_BUCKET,
    accessKeyId: process.env.R2_ACCESS_KEY_ID,
    secretAccessKey: process.env.R2_SECRET_ACCESS_KEY,
  },
}

// Fail-closed kill switch for the bill create/pay write paths. Both write
// into the SAME MongoDB collections the production web app owns, using a
// schema shape that's missing fields the web app's billing engine and
// reports require (see docs/migration audit). Read live (not cached on
// `env`) so it can be toggled without a redeploy, and so tests can flip it
// per-case. Disabled unless explicitly set to "true".
export function billWritesEnabled(): boolean {
  return process.env.BILL_WRITES_ENABLED === "true"
}

// Fail-closed kill switch for complaint status changes. Mobile's status
// vocabulary (Open/In progress/Resolved/Rejected) does not map cleanly onto
// web's canonical enum (PENDING/APPROVED/REJECTED/CLOSED/EXPIRED — see
// docs/migration audit) — writing a guessed mapping risks misrepresenting a
// real complaint's state to production admins. Disabled unless explicitly
// set to "true", pending a real product decision on the mapping.
export function complaintStatusWritesEnabled(): boolean {
  return process.env.COMPLAINT_STATUS_WRITES_ENABLED === "true"
}
