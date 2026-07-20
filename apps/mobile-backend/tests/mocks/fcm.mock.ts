import { vi } from "vitest"

// Mock for src/services/fcm.ts. Use with vi.mock in a test file, e.g.:
//
//   import { sendFcmToMemberMock, sendFcmToSocietyMock, sendFcmToUserMock } from "../mocks/fcm.mock.js"
//   vi.mock("../../src/services/fcm.js", () => ({
//     sendFcmToUser: sendFcmToUserMock,
//     sendFcmToMember: sendFcmToMemberMock,
//     sendFcmToSociety: sendFcmToSocietyMock,
//   }))
//
// so nothing ever calls real Firebase.
export const sendFcmToUserMock = vi.fn(async (
  _userId: string,
  _payload: { title: string; body: string },
  _data?: Record<string, string>,
): Promise<void> => {})

export const sendFcmToMemberMock = vi.fn(async (
  _memberId: string,
  _payload: { title: string; body: string },
  _data?: Record<string, string>,
): Promise<void> => {})

export const sendFcmToSocietyMock = vi.fn(async (
  _societyId: string,
  _payload: { title: string; body: string },
  _data?: Record<string, string>,
): Promise<void> => {})
