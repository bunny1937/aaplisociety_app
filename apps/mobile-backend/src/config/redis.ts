import { Redis } from "ioredis"
import { env } from "./env.js"
import { logger } from "../lib/logger.js"

export const redis = new Redis(env.redisUrl, { maxRetriesPerRequest: null })
export const redisSub = redis.duplicate()

redis.on("error", (err) => logger.error({ err }, "[redis] client error"))
redisSub.on("error", (err) => logger.error({ err }, "[redis] sub client error"))
