import { describe, it, expect, afterEach } from "vitest"
import type { Server } from "node:http"
import request from "supertest"
import autocannon from "autocannon"
import { createApp } from "../helpers/app.js"

// Scope: a modest smoke-test foundation, not a full load-testing harness.
// Real capacity/latency benchmarking under sustained load is explicitly out
// of scope for this pass - these three checks just prove /health responds
// fast for a single request, survives 20 concurrent requests, and survives a
// short real burst of traffic via autocannon without errors.

describe("GET /health basic performance smoke tests", () => {
  const app = createApp()

  it("responds well under 200ms for a single request", async () => {
    const start = Date.now()
    const res = await request(app).get("/health")
    const elapsed = Date.now() - start
    expect(res.status).toBe(200)
    expect(elapsed).toBeLessThan(200)
  })

  it("handles 20 concurrent requests, all returning 200", async () => {
    const results = await Promise.all(
      Array.from({ length: 20 }, () => request(app).get("/health")),
    )
    expect(results).toHaveLength(20)
    for (const res of results) {
      expect(res.status).toBe(200)
      expect(res.body).toEqual({ ok: true })
    }
  })

  describe("short real burst via autocannon", () => {
    let server: Server
    let baseUrl: string

    afterEach(async () => {
      if (server) await new Promise((resolve) => server.close(resolve))
    })

    it("survives a brief real concurrent burst with zero non-2xx responses", async () => {
      server = createApp().listen(0)
      const address = server.address()
      if (address === null || typeof address === "string") throw new Error("expected a bound TCP port")
      baseUrl = `http://127.0.0.1:${address.port}`

      const result = await autocannon({
        url: `${baseUrl}/health`,
        connections: 5,
        duration: 1,
      })

      expect(result.non2xx).toBe(0)
      expect(result.errors).toBe(0)
    }, 15000)
  })
})
