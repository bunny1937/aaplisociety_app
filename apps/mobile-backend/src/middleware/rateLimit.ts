import rateLimit, { ipKeyGenerator } from "express-rate-limit"

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

// Guards Brevo send volume and the recipient's inbox from spam - a forgotten
// password only needs a handful of code requests per window. Counts every
// request (no skipSuccessfulRequests) since a successful send is exactly
// what floods the inbox. Keyed by the requested identifier, not IP: this
// throttles "how many codes can account X receive," which is the actual
// resource being protected - IP-keying would instead throttle "how many
// different accounts can this IP request for," letting one shared IP (an
// office NAT, or many independent requests in quick succession) exhaust the
// bucket for everyone behind it regardless of which account they're after.
export const forgotPasswordLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 3,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req) => {
    const identifier = (req as any).body?.identifier
    return typeof identifier === "string" && identifier.trim()
      ? identifier.trim().toLowerCase()
      : ipKeyGenerator(req.ip ?? "")
  },
  message: { error: "Too many reset requests, try again later" },
})

// A reset code is a 6-digit value (same brute-force surface as the visitor
// pass OTP) - only failed attempts count, mirrored on passVerifyLimiter
// including its limit (20, not 10: a few mistyped codes/passwords in a row
// is normal user behavior, not abuse).
export const resetPasswordLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 20,
  standardHeaders: true,
  legacyHeaders: false,
  skipSuccessfulRequests: true,
  message: { error: "Too many attempts, try again later" },
})

// SOS raises a society-wide emergency alert — must never itself be usable as
// a denial-of-service on security's attention. Keyed by userId (not IP)
// since this is an authenticated route and IP-based limiting alone would
// under-throttle a compromised account behind a shared/rotating IP.
export const sosLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 3,
  standardHeaders: true,
  legacyHeaders: false,
  // Falls back to IP (IPv6-safely normalized per express-rate-limit's own
  // guidance — a raw req.ip fallback here fails its runtime validation and
  // silently under-throttles IPv6 clients by subnet) if req.auth is somehow
  // absent, though requireAuth on this router means it never should be.
  keyGenerator: (req) => (req as any).auth?.userId ?? ipKeyGenerator(req.ip ?? ""),
  message: { error: "Too many SOS alerts from this account, please wait before raising another" },
})

// A visitor pass OTP is a 6-digit code (1e6 possibilities) — with no
// throttling this is brute-forceable well within a normal test's timeout.
// Only failed attempts count, so a guard rapidly verifying many legitimate
// passes in a row is never blocked.
export const passVerifyLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 20,
  standardHeaders: true,
  legacyHeaders: false,
  skipSuccessfulRequests: true,
  // Falls back to IP (IPv6-safely normalized per express-rate-limit's own
  // guidance — a raw req.ip fallback here fails its runtime validation and
  // silently under-throttles IPv6 clients by subnet) if req.auth is somehow
  // absent, though requireAuth on this router means it never should be.
  keyGenerator: (req) => (req as any).auth?.userId ?? ipKeyGenerator(req.ip ?? ""),
  message: { error: "Too many failed pass verification attempts, please wait before retrying" },
})
