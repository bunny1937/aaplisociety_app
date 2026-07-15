import { describe, it, expect } from "vitest"
import request from "supertest"
import { ROLES } from "@aapli/constants"
import { createApp } from "../helpers/app.js"
import { bearerToken, authHeader } from "../helpers/auth.js"

const app = createApp()

// Express 4 does NOT forward a rejected promise from an async route handler
// to error middleware on its own - without express-async-errors patched in
// (see src/app.ts), a thrown/rejected error inside an async handler (e.g. a
// Mongoose CastError from a malformed :id) leaves the request hanging
// forever instead of responding. This proves the patch + global errorHandler
// are actually wired together, not just unit-tested in isolation.
describe("an error thrown inside an async route handler is caught and answered", () => {
  it("returns a generic JSON 500 (not a hang, not an HTML stack trace) for a malformed :id CastError", async () => {
    const token = bearerToken({ role: ROLES.MEMBER })
    const res = await request(app)
      .post("/v1/visitors/not-a-valid-object-id/decision")
      .set(authHeader(token))
      .send({ decision: "approve" })

    expect(res.status).toBe(500)
    expect(res.body).toEqual({ error: "Internal server error" })
    expect(JSON.stringify(res.body)).not.toMatch(/CastError|ObjectId|at model\.Query/)
  })
})
