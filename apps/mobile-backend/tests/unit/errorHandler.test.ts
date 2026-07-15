import { describe, it, expect, vi } from "vitest"
import { errorHandler } from "../../src/middleware/errorHandler.js"

describe("errorHandler", () => {
  it("logs the error and responds with a generic JSON 500, never leaking the message/stack to the client", () => {
    const err = new Error("boom, this contains internal detail that must not reach clients")
    const logError = vi.fn()
    const req = { log: { error: logError } } as any
    const json = vi.fn()
    const status = vi.fn(() => ({ json }))
    const res = { status, headersSent: false } as any
    const next = vi.fn()

    errorHandler(err, req, res, next)

    expect(logError).toHaveBeenCalledWith({ err }, "unhandled error")
    expect(status).toHaveBeenCalledWith(500)
    expect(json).toHaveBeenCalledWith({ error: "Internal server error" })
    expect(JSON.stringify(json.mock.calls[0])).not.toContain("boom")
  })

  it("delegates to Express's default handler via next(err) once headers are already sent", () => {
    const err = new Error("late error")
    const req = { log: { error: vi.fn() } } as any
    const status = vi.fn()
    const res = { headersSent: true, status } as any
    const next = vi.fn()

    errorHandler(err, req, res, next)

    expect(next).toHaveBeenCalledWith(err)
    expect(status).not.toHaveBeenCalled()
  })
})
