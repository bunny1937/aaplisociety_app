import { Server } from "socket.io"
import type { Server as HttpServer } from "node:http"
import { createAdapter } from "@socket.io/redis-adapter"
import { redis, redisSub } from "../config/redis.js"
import { verifyAccess } from "../lib/jwt.js"
import { room } from "@aapli/constants"
import { env } from "../config/env.js"

export let io: Server

export function initSocket(httpServer: HttpServer) {
  io = new Server(httpServer, { path: "/socket", cors: { origin: env.corsOrigins, credentials: true } })
  io.adapter(createAdapter(redis, redisSub))

  io.use((socket, next) => {
    try {
      const token = socket.handshake.auth?.token as string
      const claims = verifyAccess(token)
      ;(socket.data as any).claims = claims
      next()
    } catch {
      next(new Error("unauthorized"))
    }
  })

  io.on("connection", (socket) => {
    const c = (socket.data as any).claims
    if (c.societyId) socket.join(room.society(c.societyId))
    if (c.memberId) socket.join(room.member(c.memberId))
    if (c.userId) socket.join(room.user(c.userId))
    if (c.role === "Security" && c.societyId) socket.join(room.security(c.societyId))
  })

  return io
}
