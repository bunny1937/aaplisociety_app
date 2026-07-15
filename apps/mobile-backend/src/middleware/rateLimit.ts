import rateLimit from "express-rate-limit"

// Only failed attempts (401/400/etc) count against the limit - a legitimate
// user logging in repeatedly never gets locked out, only credential-stuffing
// / brute-force patterns do. In-memory per process: fine for a single
// instance; behind multiple instances each carries its own counter, so the
// effective limit is (limit * instanceCount) until this is backed by a
// shared Redis store.
export const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 10,
  standardHeaders: true,
  legacyHeaders: false,
  skipSuccessfulRequests: true,
  message: { error: "Too many login attempts, try again later" },
})
