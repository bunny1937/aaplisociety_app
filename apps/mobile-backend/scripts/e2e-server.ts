// Standalone, isolated backend for Flutter E2E: real Express app (createApp()),
// real in-memory MongoDB (mongodb-memory-server - a genuine mongod process, not
// a mock), seeded with one known test user. Never touches the real dev/Atlas
// database. Run with `pnpm e2e:server`, stop with Ctrl+C or SIGTERM.
import http from "node:http"
import bcrypt from "bcryptjs"
import { MongoMemoryServer } from "mongodb-memory-server"

process.env.JWT_SECRET ??= "e2e-jwt-secret"
process.env.REFRESH_SECRET ??= "e2e-refresh-secret"
process.env.REDIS_URL ??= "redis://localhost:6379/0" // never actually connected to by createApp()
const port = Number(process.env.E2E_PORT ?? 5055)

async function main() {
  const mongod = await MongoMemoryServer.create()
  process.env.MONGODB_URI = mongod.getUri()

  const mongoose = (await import("mongoose")).default
  await mongoose.connect(process.env.MONGODB_URI)

  const { User, Types } = await import("../src/models/index.js")
  const { createApp } = await import("../src/app.js")

  const societyId = new Types.ObjectId()
  const memberId = new Types.ObjectId()
  await User.create({
    username: "e2e_member",
    email: "e2e@example.com",
    passwordHash: await bcrypt.hash("E2ePass123", 10),
    role: "Member",
    societyId,
    memberId,
    profiles: [{
      societyId, memberId, role: "Member",
      flatNo: "E2E-101", wing: "E", societyName: "E2E Test Society", status: "active",
    }],
    isActive: true,
  })

  const server = http.createServer(createApp())
  server.listen(port, () => {
    console.log(`[e2e-server] ready on http://localhost:${port}`)
    console.log(`[e2e-server] seeded user: e2e_member / E2ePass123`)
  })

  const shutdown = async () => {
    server.close()
    await mongoose.disconnect()
    await mongod.stop()
    process.exit(0)
  }
  process.on("SIGTERM", shutdown)
  process.on("SIGINT", shutdown)
}

main().catch((e) => { console.error(e); process.exit(1) })
