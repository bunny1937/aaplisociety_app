import { describe, it, expect } from "vitest"
import request from "supertest"
import { ROLES } from "@aapli/constants"
import { createApp } from "../helpers/app.js"
import { bearerToken, authHeader } from "../helpers/auth.js"

const app = createApp()

describe("payload validation enforces real limits, not just types", () => {
  it("rejects a complaint description past its zod max length (1000) with 400", async () => {
    const token = bearerToken({ role: ROLES.MEMBER })
    const tooLong = "x".repeat(1001)
    const res = await request(app).post("/v1/complaints").set(authHeader(token)).send({
      category: "noise", title: "Valid title here", description: tooLong,
    })
    expect(res.status).toBe(400)
    expect(res.body.error.fieldErrors.description).toBeTruthy()
  })

  // There is no SQL database anywhere in this stack, so classic SQL-injection
  // testing does not apply. The equivalent attack surface here is a
  // NoSQL-injection-shaped payload (a Mongo query operator object, e.g.
  // {"$gt": ""}) sneaking into a field that ends up inside a Mongoose query
  // (User.findOne({ $or: [{ username: identifier }, ...] })). zod's type
  // enforcement (identifier: z.string()) is what stands between the raw
  // request body and that query, so this test proves the object is rejected
  // at the validation layer and never reaches Mongoose as a live operator.
  it("rejects a NoSQL-injection-shaped identifier object (not a string) with 400", async () => {
    const res = await request(app).post("/v1/auth/login").send({
      identifier: { $gt: "" }, password: "whatever1",
    })
    expect(res.status).toBe(400)
    expect(res.body.error.fieldErrors.identifier).toBeTruthy()
  })
})

describe("CORS enforces an origin allowlist", () => {
  it("reflects an allowlisted origin in Access-Control-Allow-Origin", async () => {
    const origin = "https://aaplisociety.vercel.app"
    const res = await request(app).get("/health").set("Origin", origin)
    expect(res.status).toBe(200)
    expect(res.headers["access-control-allow-origin"]).toBe(origin)
    expect(res.headers["access-control-allow-credentials"]).toBe("true")
  })

  it("omits Access-Control-Allow-Origin for a non-allowlisted origin", async () => {
    const res = await request(app).get("/health").set("Origin", "https://evil-caller.invalid")
    expect(res.status).toBe(200)
    expect(res.headers["access-control-allow-origin"]).toBeUndefined()
  })

  it("still serves requests with no Origin header at all (native mobile clients)", async () => {
    const res = await request(app).get("/health")
    expect(res.status).toBe(200)
    expect(res.body).toEqual({ ok: true })
  })
})

describe("login is rate limited", () => {
  it("returns 429 once repeated rapid attempts from the same client exceed the limit", async () => {
    const identifier = `rate-limited-${Math.floor(Math.random() * 1e6)}`
    const attempts = await Promise.all(
      Array.from({ length: 15 }, () =>
        request(app).post("/v1/auth/login").send({ identifier, password: "wrong-password" }),
      ),
    )
    const statuses = attempts.map((res) => res.status)
    expect(statuses).toContain(429)
    expect(statuses.every((s) => s === 401 || s === 429)).toBe(true)
  })
})

// Not tested here, and out of scope with a reason:
// - CSRF: this API is a pure stateless Bearer-token JSON API; there is no
//   cookie-based ambient auth session anywhere in this codebase for CSRF to
//   exploit.
// - XSS: this is a JSON API, not server-rendered HTML, so there is no HTML
//   sink for injected script to execute in.
// - File upload validation: src/services/storage.ts only issues presigned
//   S3/R2 URLs for direct client uploads; this Express server never receives
//   file bytes, so there is no upload endpoint to fuzz.
