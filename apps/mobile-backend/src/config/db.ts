import mongoose from "mongoose"
import { env } from "./env.js"
import { logger } from "../lib/logger.js"

export async function connectDb(): Promise<void> {
  mongoose.set("strictQuery", true)
  await mongoose.connect(env.mongoUri)
  logger.info("[db] connected")
}
