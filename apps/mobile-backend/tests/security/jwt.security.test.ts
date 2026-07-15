import { describe, it, expect } from "vitest"
import request from "supertest"
import jwt from "jsonwebtoken"
import { createApp } from "../helpers/app.js"
import { bearerToken } from "../helpers/auth.js"
import { env } from "../../src/config/env.js"
import { User } from "../../src/models/index.js"
import { makeUser } from "../factories/index.js"
import { randomObjectId } from "../utils/randomObjectId.js"

const app = createApp()

describe("JWT edge cases on a protected route (GET /v1/auth/me)", () => {
  it("rejects a token with a tampered signature (401)", async () => {
    const token = bearerToken()
    const lastChar = token.at(-1)
    const tampered = token.slice(0, -1) + (lastChar === "a" ? "b" : "a")

    const res = await request(app).get("/v1/auth/me").set("Authorization", `Bearer ${tampered}`)
    expect(res.status).toBe(401)
    expect(res.body).toEqual({ error: "Invalid token" })
  })

  it("rejects a token signed with the wrong secret (401)", async () => {
    const forged = jwt.sign({ userId: "abc", role: "Admin" }, "not-the-real-secret", { expiresIn: "15m" })
    const res = await request(app).get("/v1/auth/me").set("Authorization", `Bearer ${forged}`)
    expect(res.status).toBe(401)
    expect(res.body).toEqual({ error: "Invalid token" })
  })

  it("rejects an expired token (401)", async () => {
    const expired = jwt.sign({ userId: "abc", role: "Admin" }, env.jwtSecret, { expiresIn: "-1s" })
    const res = await request(app).get("/v1/auth/me").set("Authorization", `Bearer ${expired}`)
    expect(res.status).toBe(401)
    expect(res.body).toEqual({ error: "Invalid token" })
  })

  it("rejects a missing Authorization header (401 No token)", async () => {
    const res = await request(app).get("/v1/auth/me")
    expect(res.status).toBe(401)
    expect(res.body).toEqual({ error: "No token" })
  })

  it("rejects a header using a non-Bearer scheme prefix (401 Invalid token)", async () => {
    const token = bearerToken()
    // "Token <jwt>" is not a valid JWT as a single string, and readToken() only
    // strips a "Bearer " prefix - anything else is passed through whole and
    // fails to verify.
    const res = await request(app).get("/v1/auth/me").set("Authorization", `Token ${token}`)
    expect(res.status).toBe(401)
    expect(res.body).toEqual({ error: "Invalid token" })
  })

  it("FINDING: a raw token with no scheme prefix at all is still accepted (the 'Bearer ' prefix is not actually enforced)", async () => {
    // src/middleware/auth.ts readToken() does:
    //   req.headers.authorization?.replace(/^Bearer\s+/i, "")
    // If the header doesn't start with "Bearer ", the regex is a no-op and the
    // ENTIRE header value is used as the token verbatim. So sending the raw,
    // valid token with no "Bearer " prefix at all still authenticates
    // successfully. This documents that current (mildly permissive) behavior
    // rather than asserting the commonly-assumed 401 - it is not a broken
    // token check, just a lenient one that doesn't require the RFC 6750
    // "Bearer" scheme name to be present.
    const userId = randomObjectId()
    await User.create({ ...makeUser(), _id: userId })
    const token = bearerToken({ userId: String(userId) })
    const res = await request(app).get("/v1/auth/me").set("Authorization", token)
    expect(res.status).toBe(200)
  })
})
