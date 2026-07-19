import { describe, it, expect, vi, beforeEach } from "vitest"

const sendMock = vi.fn(async () => ({}))
vi.mock("@aws-sdk/client-s3", () => ({
  S3Client: vi.fn().mockImplementation(() => ({ send: sendMock })),
  PutObjectCommand: vi.fn().mockImplementation((input) => ({ input })),
  GetObjectCommand: vi.fn().mockImplementation((input) => ({ input })),
}))
vi.mock("@aws-sdk/s3-request-presigner", () => ({
  getSignedUrl: vi.fn(async () => "https://mock.invalid/presigned"),
}))

beforeEach(() => sendMock.mockClear())

describe("uploadBuffer", () => {
  it("sends a PutObjectCommand with the given key, body, and contentType", async () => {
    const { uploadBuffer } = await import("../../src/services/storage.js")
    const body = Buffer.from("fake pdf bytes")
    await uploadBuffer("society1/tenant-requests/contract/uuid.pdf", body, "application/pdf")

    expect(sendMock).toHaveBeenCalledTimes(1)
    const command = sendMock.mock.calls[0][0]
    expect(command.input.Key).toBe("society1/tenant-requests/contract/uuid.pdf")
    expect(command.input.Body).toBe(body)
    expect(command.input.ContentType).toBe("application/pdf")
  })
})
