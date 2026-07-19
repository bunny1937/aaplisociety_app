import { vi } from "vitest"

// Mock for src/lib/brevo.ts. Use with vi.mock in a test file, e.g.:
//
//   import { sendEmailMock } from "../mocks/brevo.mock.js"
//   vi.mock("../../src/lib/brevo.js", () => ({
//     sendEmail: sendEmailMock,
//     resetCodeEmailHtml: (code: string) => `<code>${code}</code>`,
//   }))
//
// so nothing ever calls real Brevo.
export const sendEmailMock = vi.fn(async (
  _args: { to: string; subject: string; html: string },
): Promise<void> => {})
