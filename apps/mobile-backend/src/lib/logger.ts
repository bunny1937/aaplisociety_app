import pino from "pino"

// Plain JSON logs everywhere (prod-safe, no extra pretty-printer dep).
// Silent in tests so vitest output stays readable; override with LOG_LEVEL.
export const logger = pino({
  level: process.env.LOG_LEVEL ?? (process.env.NODE_ENV === "test" ? "silent" : "info"),
})
