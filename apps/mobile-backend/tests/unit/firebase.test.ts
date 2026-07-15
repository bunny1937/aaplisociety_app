import { describe, it, expect } from "vitest"
import { validateFirebaseConfig } from "../../src/config/firebase.js"

describe("validateFirebaseConfig", () => {
  it("does nothing when FIREBASE_SA_JSON is unset (FCM is optional in dev)", () => {
    expect(() => validateFirebaseConfig(undefined)).not.toThrow()
  })

  it("throws fast for a value that isn't valid JSON", () => {
    expect(() => validateFirebaseConfig("not-json-at-all")).toThrow(/not valid JSON/)
  })

  it("throws fast when required service-account fields are missing", () => {
    expect(() => validateFirebaseConfig(JSON.stringify({ project_id: "p" })))
      .toThrow(/missing required field.*private_key.*client_email/)
  })

  it("passes for a well-formed service account JSON", () => {
    const sa = JSON.stringify({ project_id: "p", private_key: "k", client_email: "e@x.com" })
    expect(() => validateFirebaseConfig(sa)).not.toThrow()
  })
})
