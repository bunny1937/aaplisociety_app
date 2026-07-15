import { vi } from "vitest"

// Mock for src/services/fcm.ts. Use with vi.mock in a test file, e.g.:
//
//   import { sendFcmToUserMock } from "../mocks/fcm.mock.js"
//   vi.mock("../../src/services/fcm.js", () => ({ sendFcmToUser: sendFcmToUserMock }))
//
// so nothing ever calls real Firebase.
export const sendFcmToUserMock = vi.fn(async (
  _userId: string,
  _payload: { title: string; body: string },
  _data?: Record<string, string>,
): Promise<void> => {})
