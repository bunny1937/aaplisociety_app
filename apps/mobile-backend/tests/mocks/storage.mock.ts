import { vi } from "vitest"

// Mock for src/services/storage.ts. Use with vi.mock in a test file, e.g.:
//
//   import { buildKeyMock, presignUploadMock, presignDownloadMock } from "../mocks/storage.mock.js"
//   vi.mock("../../src/services/storage.js", () => ({
//     buildKey: buildKeyMock,
//     presignUpload: presignUploadMock,
//     presignDownload: presignDownloadMock,
//   }))
//
// so nothing ever calls real S3/R2.
export const buildKeyMock = vi.fn((societyId: string, folder: string, ext: string): string =>
  `${societyId}/${folder}/mock-key.${ext.replace(/^\./, "")}`,
)

export const presignUploadMock = vi.fn(async (
  _key: string,
  _contentType: string,
): Promise<string> => "https://mock-upload.invalid/presigned-put")

export const presignDownloadMock = vi.fn(async (
  _key: string,
): Promise<string> => "https://mock-download.invalid/presigned-get")
