import mongoose from "mongoose"
import { redis } from "../config/redis.js"

export interface DependencyHealth {
  ok: boolean
  status: string
  replicaSet?: string | null
  error?: string
}

export interface HealthReport {
  ok: boolean
  mongo: DependencyHealth
  redis: DependencyHealth
}

function withTimeout<T>(p: Promise<T>, ms: number): Promise<T> {
  return Promise.race([
    p,
    new Promise<T>((_, reject) => setTimeout(() => reject(new Error("timeout")), ms)),
  ])
}

// Checks actual reachability, not just "did connectDb() run once at
// startup" — a Mongo/Redis connection can die hours after boot without the
// process crashing. Also confirms the replica-set status this app depends
// on for every change-stream-driven notification (see config/db.ts's
// assertReplicaSet(), which only runs once at startup; this makes the same
// fact continuously checkable).
async function checkMongo(): Promise<DependencyHealth> {
  const state = mongoose.connection.readyState // 0 disconnected, 1 connected, 2 connecting, 3 disconnecting
  const stateNames = ["disconnected", "connected", "connecting", "disconnecting"]
  if (state !== 1) {
    return { ok: false, status: stateNames[state] ?? String(state) }
  }
  try {
    const result = await withTimeout(mongoose.connection.db!.admin().command({ hello: 1 }), 1500)
    return { ok: true, status: "connected", replicaSet: result.setName ?? null }
  } catch (err) {
    return { ok: false, status: "connected", error: err instanceof Error ? err.message : "unknown error" }
  }
}

// Reads ioredis's own connection-state machine rather than issuing a PING —
// this app's Redis client is configured with maxRetriesPerRequest: null
// (see config/redis.ts), meaning a command issued while disconnected queues
// indefinitely rather than failing fast. A status check can't hang.
function checkRedis(): DependencyHealth {
  const status = redis.status // "connecting" | "connect" | "ready" | "close" | "reconnecting" | "end"
  return { ok: status === "ready", status }
}

export async function getHealthReport(): Promise<HealthReport> {
  const [mongo, redisHealth] = await Promise.all([checkMongo(), Promise.resolve(checkRedis())])
  return { ok: mongo.ok && redisHealth.ok, mongo, redis: redisHealth }
}
