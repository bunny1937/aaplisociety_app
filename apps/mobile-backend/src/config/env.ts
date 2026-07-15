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
  r2: {
    endpoint: process.env.R2_ENDPOINT,
    bucket: process.env.R2_BUCKET,
    accessKeyId: process.env.R2_ACCESS_KEY_ID,
    secretAccessKey: process.env.R2_SECRET_ACCESS_KEY,
  },
}
