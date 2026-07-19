import { describe, it, expect, vi } from "vitest"
import request from "supertest"
import bcrypt from "bcryptjs"
import jwt from "jsonwebtoken"
import { ROLES } from "@aapli/constants"
import { createApp } from "../helpers/app.js"
import { bearerToken, authHeader } from "../helpers/auth.js"
import { hashPassword } from "../factories/index.js"
import { randomObjectId } from "../utils/randomObjectId.js"
import { User, RefreshToken, Member, Society } from "../../src/models/index.js"
import { verifyAccess } from "../../src/lib/jwt.js"
import { makeMember, makeSociety } from "../factories/index.js"
import { sendEmailMock } from "../mocks/brevo.mock.js"

// Mocked so this suite never calls real Brevo — see tests/mocks/brevo.mock.ts.
// Factory imports the mock module dynamically (rather than referencing a
// top-level imported binding) so it isn't affected by vi.mock's hoisting to
// the top of the file.
vi.mock("../../src/lib/brevo.js", async () => {
  const mock = await import("../mocks/brevo.mock.js")
  return {
    sendEmail: mock.sendEmailMock,
    resetCodeEmailHtml: (code: string) => `<p>${code}</p>`,
  }
})

const app = createApp()
const PASSWORD = "Passw0rd!"

function codeFromLastEmail(): string {
  const html = sendEmailMock.mock.calls.at(-1)?.[0]?.html as string
  const match = html?.match(/(\d{6})/)
  if (!match) throw new Error("No 6-digit code found in last sent email")
  return match[1]
}

async function createSingleProfileUser(overrides: { isActive?: boolean } = {}) {
  const societyId = randomObjectId()
  const memberId = randomObjectId()
  const passwordHash = await hashPassword(PASSWORD)
  const user = await User.create({
    username: `member.${Math.floor(Math.random() * 1e6)}`,
    email: `member.${Math.floor(Math.random() * 1e6)}@example.com`,
    passwordHash,
    role: ROLES.MEMBER,
    societyId,
    memberId,
    profiles: [{
      societyId, memberId, role: ROLES.MEMBER,
      flatNo: "A-101", wing: "A", societyName: "Sunrise CHS", status: "Active",
    }],
    isActive: overrides.isActive ?? true,
  })
  return { user, societyId, memberId }
}

describe("POST /v1/auth/login", () => {
  it("returns 401 Invalid credentials for wrong password", async () => {
    const { user } = await createSingleProfileUser()
    const res = await request(app).post("/v1/auth/login").send({ identifier: user.username, password: "wrong-password" })
    expect(res.status).toBe(401)
    expect(res.body).toEqual({ error: "Invalid credentials" })
  })

  it("returns 401 for an unknown identifier", async () => {
    const res = await request(app).post("/v1/auth/login").send({ identifier: "nobody.here", password: "whatever1" })
    expect(res.status).toBe(401)
    expect(res.body).toEqual({ error: "Invalid credentials" })
  })

  it("returns 401 for an inactive user even with the correct password", async () => {
    const { user } = await createSingleProfileUser({ isActive: false })
    const res = await request(app).post("/v1/auth/login").send({ identifier: user.username, password: PASSWORD })
    expect(res.status).toBe(401)
    expect(res.body).toEqual({ error: "Invalid credentials" })
  })

  it("returns 400 with a zod-flatten error shape for missing/short fields", async () => {
    const res = await request(app).post("/v1/auth/login").send({ identifier: "ab", password: "123" })
    expect(res.status).toBe(400)
    expect(res.body.error.fieldErrors).toBeDefined()
    expect(res.body.error.fieldErrors.identifier).toBeTruthy()
    expect(res.body.error.fieldErrors.password).toBeTruthy()
  })

  it("logs in a single-profile user and issues tokens whose claims match the seeded profile", async () => {
    const { user, societyId, memberId } = await createSingleProfileUser()
    const res = await request(app).post("/v1/auth/login").send({ identifier: user.username, password: PASSWORD })
    expect(res.status).toBe(200)
    expect(res.body.tokens.accessToken).toEqual(expect.any(String))
    expect(res.body.tokens.refreshToken).toEqual(expect.any(String))

    const claims = verifyAccess(res.body.tokens.accessToken)
    expect(claims.role).toBe(ROLES.MEMBER)
    expect(claims.societyId).toBe(String(societyId))
    expect(claims.memberId).toBe(String(memberId))
  })

  it("returns needsProfileSelect + a pending selectToken for a multi-profile user with no activeProfileId", async () => {
    const societyId1 = randomObjectId()
    const societyId2 = randomObjectId()
    const passwordHash = await hashPassword(PASSWORD)
    const user = await User.create({
      username: `multi.${Math.floor(Math.random() * 1e6)}`,
      email: `multi.${Math.floor(Math.random() * 1e6)}@example.com`,
      passwordHash,
      role: ROLES.MEMBER,
      societyId: societyId1,
      memberId: randomObjectId(),
      profiles: [
        { societyId: societyId1, memberId: randomObjectId(), role: ROLES.MEMBER, flatNo: "A-101", wing: "A", societyName: "Sunrise CHS", status: "Active" },
        { societyId: societyId2, memberId: randomObjectId(), role: ROLES.MEMBER, flatNo: "B-202", wing: "B", societyName: "Palm Residency", status: "Active" },
      ],
      isActive: true,
    })

    const res = await request(app).post("/v1/auth/login").send({ identifier: user.username, password: PASSWORD })
    expect(res.status).toBe(200)
    expect(res.body.needsProfileSelect).toBe(true)
    expect(res.body.selectToken).toEqual(expect.any(String))
    expect(res.body.profiles).toHaveLength(2)
    expect(res.body.profiles.map((p: any) => p.societyName).sort()).toEqual(["Palm Residency", "Sunrise CHS"])

    const claims = verifyAccess(res.body.selectToken)
    expect(claims.pending).toBe(true)
  })
})

describe("POST /v1/auth/switch-profile", () => {
  async function createMultiProfileUser() {
    const societyId1 = randomObjectId()
    const societyId2 = randomObjectId()
    const passwordHash = await hashPassword(PASSWORD)
    const user = await User.create({
      username: `multi.${Math.floor(Math.random() * 1e6)}`,
      email: `multi.${Math.floor(Math.random() * 1e6)}@example.com`,
      passwordHash,
      role: ROLES.MEMBER,
      societyId: societyId1,
      memberId: randomObjectId(),
      profiles: [
        { societyId: societyId1, memberId: randomObjectId(), role: ROLES.MEMBER, flatNo: "A-101", wing: "A", societyName: "Sunrise CHS", status: "Active" },
        { societyId: societyId2, memberId: randomObjectId(), role: ROLES.MEMBER, flatNo: "B-202", wing: "B", societyName: "Palm Residency", status: "Active" },
      ],
      isActive: true,
    })
    const loginRes = await request(app).post("/v1/auth/login").send({ identifier: user.username, password: PASSWORD })
    return { user, selectToken: loginRes.body.selectToken as string }
  }

  it("switches to a valid profile, returns tokens, and persists activeProfileId", async () => {
    const { user, selectToken } = await createMultiProfileUser()
    const targetProfileId = String((user.profiles[1] as any)._id)

    const res = await request(app)
      .post("/v1/auth/switch-profile")
      .set(authHeader(selectToken))
      .send({ profileId: targetProfileId })

    expect(res.status).toBe(200)
    expect(res.body.tokens.accessToken).toEqual(expect.any(String))

    const persisted = await User.findById(user._id)
    expect(String(persisted!.activeProfileId)).toBe(targetProfileId)
  })

  it("returns 404 for an unknown profileId", async () => {
    const { selectToken } = await createMultiProfileUser()
    const res = await request(app)
      .post("/v1/auth/switch-profile")
      .set(authHeader(selectToken))
      .send({ profileId: String(randomObjectId()) })
    expect(res.status).toBe(404)
    expect(res.body).toEqual({ error: "Profile not found" })
  })

  it("critical: a pending selectToken is rejected by GET /auth/me with 403 Profile selection required", async () => {
    const { selectToken } = await createMultiProfileUser()
    const res = await request(app).get("/v1/auth/me").set(authHeader(selectToken))
    expect(res.status).toBe(403)
    expect(res.body).toEqual({ error: "Profile selection required" })
  })
})

describe("POST /v1/auth/refresh", () => {
  it("rotates the refresh token: old one is marked revoked, new tokens are issued", async () => {
    const { user } = await createSingleProfileUser()
    const loginRes = await request(app).post("/v1/auth/login").send({ identifier: user.username, password: PASSWORD })
    const originalRefreshToken = loginRes.body.tokens.refreshToken as string

    const storedBefore = await RefreshToken.findOne({ userId: user._id })
    expect(storedBefore!.revoked).toBe(false)

    const res = await request(app).post("/v1/auth/refresh").send({ refreshToken: originalRefreshToken })
    expect(res.status).toBe(200)
    expect(res.body.tokens.accessToken).toEqual(expect.any(String))
    expect(res.body.tokens.refreshToken).not.toBe(originalRefreshToken)

    const storedAfter = await RefreshToken.findById(storedBefore!._id)
    expect(storedAfter!.revoked).toBe(true)
  })

  it("rejects replay of an already-rotated refresh token with 401 (reuse defense)", async () => {
    const { user } = await createSingleProfileUser()
    const loginRes = await request(app).post("/v1/auth/login").send({ identifier: user.username, password: PASSWORD })
    const originalRefreshToken = loginRes.body.tokens.refreshToken as string

    await request(app).post("/v1/auth/refresh").send({ refreshToken: originalRefreshToken })
    const replay = await request(app).post("/v1/auth/refresh").send({ refreshToken: originalRefreshToken })
    expect(replay.status).toBe(401)
    expect(replay.body).toEqual({ error: "Refresh revoked" })
  })

  it("rejects a garbage token string with 401 Invalid refresh", async () => {
    const res = await request(app).post("/v1/auth/refresh").send({ refreshToken: "not-a-real-token" })
    expect(res.status).toBe(401)
    expect(res.body).toEqual({ error: "Invalid refresh" })
  })

  it("critical: stores RefreshToken.expiresAt derived from the issued JWT's own exp claim, not a hardcoded duration", async () => {
    const { user } = await createSingleProfileUser()
    const loginRes = await request(app).post("/v1/auth/login").send({ identifier: user.username, password: PASSWORD })
    const stored = await RefreshToken.findOne({ userId: user._id })
    const decoded = jwt.decode(loginRes.body.tokens.refreshToken) as { exp: number }
    expect(stored!.expiresAt.getTime()).toBe(decoded.exp * 1000)
  })
})

describe("GET /v1/auth/me", () => {
  it("returns 401 with no token", async () => {
    const res = await request(app).get("/v1/auth/me")
    expect(res.status).toBe(401)
    expect(res.body).toEqual({ error: "No token" })
  })

  it("returns the user (without passwordHash) for a valid token", async () => {
    const { user } = await createSingleProfileUser()
    const loginRes = await request(app).post("/v1/auth/login").send({ identifier: user.username, password: PASSWORD })
    const res = await request(app).get("/v1/auth/me").set(authHeader(loginRes.body.tokens.accessToken))
    expect(res.status).toBe(200)
    expect(res.body.user.username).toBe(user.username)
    expect(res.body.user).not.toHaveProperty("passwordHash")
    expect(JSON.stringify(res.body.user)).not.toContain("passwordHash")
  })

  it("attaches the linked Member and Society, projecting only safe Member fields", async () => {
    const { user, societyId, memberId } = await createSingleProfileUser()
    await Society.create({ ...makeSociety({ name: "Sunrise Complex" }), _id: societyId })
    await Member.create({
      ...makeMember({ ownerName: "Tanvi Bansal", flatType: "4BHK", panCard: "LMNOP5304B" }),
      _id: memberId,
      societyId,
    })

    const loginRes = await request(app).post("/v1/auth/login").send({ identifier: user.username, password: PASSWORD })
    const res = await request(app).get("/v1/auth/me").set(authHeader(loginRes.body.tokens.accessToken))

    expect(res.status).toBe(200)
    expect(res.body.user.member.ownerName).toBe("Tanvi Bansal")
    expect(res.body.user.member.flatType).toBe("4BHK")
    expect(res.body.user.member.parkingSlots[0].slotNumber).toBe("P-B-112")
    expect(res.body.user.member.familyMembers[0].name).toBe("Neha Sharma")
    expect(res.body.user.member).not.toHaveProperty("panCard")
    expect(res.body.user.society).toEqual({ _id: String(societyId), name: "Sunrise Complex", address: expect.any(String) })
  })

  it("returns member: null and society: null when neither is linked", async () => {
    const { user } = await createSingleProfileUser()
    const loginRes = await request(app).post("/v1/auth/login").send({ identifier: user.username, password: PASSWORD })
    const res = await request(app).get("/v1/auth/me").set(authHeader(loginRes.body.tokens.accessToken))
    expect(res.status).toBe(200)
    expect(res.body.user.member).toBeNull()
    expect(res.body.user.society).toBeNull()
  })
})

describe("POST /v1/auth/change-password", () => {
  it("returns 401 for a wrong currentPassword", async () => {
    const { user } = await createSingleProfileUser()
    const loginRes = await request(app).post("/v1/auth/login").send({ identifier: user.username, password: PASSWORD })
    const res = await request(app)
      .post("/v1/auth/change-password")
      .set(authHeader(loginRes.body.tokens.accessToken))
      .send({ currentPassword: "totally-wrong", newPassword: "NewPassw0rd!" })
    expect(res.status).toBe(401)
    expect(res.body).toEqual({ error: "Current password is incorrect" })
  })

  it("changes the password and the NEW password actually works on a subsequent login", async () => {
    const { user } = await createSingleProfileUser()
    const loginRes = await request(app).post("/v1/auth/login").send({ identifier: user.username, password: PASSWORD })
    const changeRes = await request(app)
      .post("/v1/auth/change-password")
      .set(authHeader(loginRes.body.tokens.accessToken))
      .send({ currentPassword: PASSWORD, newPassword: "NewPassw0rd!" })
    expect(changeRes.status).toBe(200)
    expect(changeRes.body).toEqual({ ok: true })

    const oldLogin = await request(app).post("/v1/auth/login").send({ identifier: user.username, password: PASSWORD })
    expect(oldLogin.status).toBe(401)

    const newLogin = await request(app).post("/v1/auth/login").send({ identifier: user.username, password: "NewPassw0rd!" })
    expect(newLogin.status).toBe(200)
    expect(newLogin.body.tokens.accessToken).toEqual(expect.any(String))
  })
})

describe("Security guard login (no profiles[], no memberId)", () => {
  it("logs in and GET /auth/me succeeds without a memberId/activeProfileId 'undefined'-string CastError", async () => {
    const societyId = randomObjectId()
    const passwordHash = await hashPassword(PASSWORD)
    const guard = await User.create({
      username: `guard.${Math.floor(Math.random() * 1e6)}`,
      name: "Test Guard",
      passwordHash,
      role: ROLES.SECURITY,
      societyId,
      // Deliberately no `profiles`, no `memberId` - matches how
      // apps/aaplisoceity_web's POST /api/admin/security-guards creates
      // guard accounts (see auth.controller.ts's issueTokens() comment).
      isActive: true,
    })

    const loginRes = await request(app).post("/v1/auth/login").send({ identifier: guard.username, password: PASSWORD })
    expect(loginRes.status).toBe(200)
    expect(loginRes.body.role).toBe(ROLES.SECURITY)

    const claims = verifyAccess(loginRes.body.tokens.accessToken)
    expect(claims.memberId).toBeUndefined()
    expect(claims.activeProfileId).toBeUndefined()

    const meRes = await request(app).get("/v1/auth/me").set(authHeader(loginRes.body.tokens.accessToken))
    expect(meRes.status).toBe(200)
    expect(meRes.body.user.member).toBeNull()
  })
})

describe("POST /v1/auth/forgot-password", () => {
  it("returns a generic 200 for an unknown identifier, without sending an email (anti-enumeration)", async () => {
    const res = await request(app).post("/v1/auth/forgot-password").send({ identifier: "nobody.here" })
    expect(res.status).toBe(200)
    expect(res.body).toEqual({ ok: true })
    expect(sendEmailMock).not.toHaveBeenCalled()
  })

  it("returns the same generic 200 when the account has no email on file, without sending an email", async () => {
    const { user } = await createSingleProfileUser()
    await User.updateOne({ _id: user._id }, { $unset: { email: 1 } })
    const res = await request(app).post("/v1/auth/forgot-password").send({ identifier: user.username })
    expect(res.status).toBe(200)
    expect(res.body).toEqual({ ok: true })
    expect(sendEmailMock).not.toHaveBeenCalled()
  })

  it("emails a 6-digit code and stores its hash on the user", async () => {
    const { user } = await createSingleProfileUser()
    const res = await request(app).post("/v1/auth/forgot-password").send({ identifier: user.username })
    expect(res.status).toBe(200)
    expect(res.body).toEqual({ ok: true })
    expect(sendEmailMock).toHaveBeenCalledWith(expect.objectContaining({ to: user.email }))

    const code = codeFromLastEmail()
    expect(code).toMatch(/^\d{6}$/)

    const persisted = await User.findById(user._id)
    expect(persisted!.get("resetCodeHash")).toEqual(expect.any(String))
    expect(persisted!.get("resetCodeExpiresAt")).toBeInstanceOf(Date)
    expect(persisted!.get("resetCodeAttempts")).toBe(0)
  })
})

describe("POST /v1/auth/reset-password", () => {
  it("returns the same generic 400 for an unknown identifier as for an invalid code (anti-enumeration)", async () => {
    const res = await request(app).post("/v1/auth/reset-password").send({ identifier: "nobody.here", code: "123456", newPassword: "NewPassw0rd!" })
    expect(res.status).toBe(400)
    expect(res.body).toEqual({ error: "Code expired or invalid, request a new one" })
  })

  it("returns 400 when no code was ever requested", async () => {
    const { user } = await createSingleProfileUser()
    const res = await request(app).post("/v1/auth/reset-password").send({ identifier: user.username, code: "123456", newPassword: "NewPassw0rd!" })
    expect(res.status).toBe(400)
    expect(res.body).toEqual({ error: "Code expired or invalid, request a new one" })
  })

  it("returns the same generic 400 for a wrong code, but still increments resetCodeAttempts server-side", async () => {
    const { user } = await createSingleProfileUser()
    await request(app).post("/v1/auth/forgot-password").send({ identifier: user.username })

    const res = await request(app).post("/v1/auth/reset-password").send({ identifier: user.username, code: "000000", newPassword: "NewPassw0rd!" })
    expect(res.status).toBe(400)
    expect(res.body).toEqual({ error: "Code expired or invalid, request a new one" })

    const persisted = await User.findById(user._id)
    expect(persisted!.get("resetCodeAttempts")).toBe(1)
  })

  it("returns 400 once resetCodeAttempts reaches the limit, even with the right code", async () => {
    const { user } = await createSingleProfileUser()
    await request(app).post("/v1/auth/forgot-password").send({ identifier: user.username })
    const code = codeFromLastEmail()

    for (let i = 0; i < 5; i++) {
      await request(app).post("/v1/auth/reset-password").send({ identifier: user.username, code: "000000", newPassword: "NewPassw0rd!" })
    }

    const res = await request(app).post("/v1/auth/reset-password").send({ identifier: user.username, code, newPassword: "NewPassw0rd!" })
    expect(res.status).toBe(400)
    expect(res.body).toEqual({ error: "Code expired or invalid, request a new one" })
  })

  it("resets the password, invalidates the code, revokes refresh tokens, and the new password works", async () => {
    const { user } = await createSingleProfileUser()

    const loginRes = await request(app).post("/v1/auth/login").send({ identifier: user.username, password: PASSWORD })
    const oldRefreshToken = loginRes.body.tokens.refreshToken as string
    const storedRefresh = await RefreshToken.findOne({ userId: user._id })
    expect(storedRefresh!.revoked).toBe(false)

    await request(app).post("/v1/auth/forgot-password").send({ identifier: user.username })
    const code = codeFromLastEmail()

    const resetRes = await request(app).post("/v1/auth/reset-password").send({ identifier: user.username, code, newPassword: "NewPassw0rd!" })
    expect(resetRes.status).toBe(200)
    expect(resetRes.body).toEqual({ ok: true })

    // Old password no longer works, new one does
    const oldLogin = await request(app).post("/v1/auth/login").send({ identifier: user.username, password: PASSWORD })
    expect(oldLogin.status).toBe(401)
    const newLogin = await request(app).post("/v1/auth/login").send({ identifier: user.username, password: "NewPassw0rd!" })
    expect(newLogin.status).toBe(200)

    // Code is single-use
    const replay = await request(app).post("/v1/auth/reset-password").send({ identifier: user.username, code, newPassword: "AnotherPassw0rd!" })
    expect(replay.status).toBe(400)

    // Pre-reset refresh token was revoked
    const refreshAfterReset = await request(app).post("/v1/auth/refresh").send({ refreshToken: oldRefreshToken })
    expect(refreshAfterReset.status).toBe(401)
    expect(refreshAfterReset.body).toEqual({ error: "Refresh revoked" })
  })
})

describe("GET /v1/auth/members", () => {
  async function createAdminAndMembers(count: number) {
    const adminSocietyId = randomObjectId()
    const passwordHash = await hashPassword(PASSWORD)
    const admin = await User.create({
      username: `admin.${Math.floor(Math.random() * 1e6)}`,
      email: `admin.${Math.floor(Math.random() * 1e6)}@example.com`,
      passwordHash,
      role: ROLES.ADMIN,
      societyId: adminSocietyId,
      memberId: randomObjectId(),
      profiles: [{
        societyId: adminSocietyId, memberId: randomObjectId(), role: ROLES.ADMIN,
        flatNo: "Office", wing: "", societyName: "Test Society", status: "Active",
      }],
      isActive: true,
    })
    const profile = admin.profiles[0] as any
    const adminToken = bearerToken({
      userId: String(admin._id),
      role: ROLES.ADMIN,
      societyId: String(adminSocietyId),
      memberId: String(profile.memberId),
      activeProfileId: String(profile._id),
    })

    const members = []
    for (let i = 0; i < count; i++) {
      const memberId = randomObjectId()
      const username = `member.${i}.${Math.floor(Math.random() * 1e6)}`
      const user = await User.create({
        username,
        email: `${username}@example.com`,
        passwordHash,
        role: ROLES.MEMBER,
        societyId: adminSocietyId,
        memberId,
        profiles: [{
          societyId: adminSocietyId, memberId, role: ROLES.MEMBER,
          flatNo: `A-${i}`, wing: "A", societyName: "Test Society", status: "Active",
        }],
        isActive: true,
      })
      members.push(user)
    }
    return { adminToken, adminSocietyId, members }
  }

  it("rejects a non-admin role with 403", async () => {
    const token = bearerToken({ role: ROLES.SECURITY })
    const res = await request(app).get("/v1/auth/members").set(authHeader(token))
    expect(res.status).toBe(403)
    expect(res.body).toEqual({ error: "Forbidden" })
  })

  it("returns the list of members in the admin's society", async () => {
    const { adminToken } = await createAdminAndMembers(2)
    const res = await request(app).get("/v1/auth/members").set(authHeader(adminToken))
    expect(res.status).toBe(200)
    expect(Array.isArray(res.body)).toBe(true)
    expect(res.body).toHaveLength(2)
    for (const m of res.body) {
      expect(m.flatNo).toEqual(expect.any(String))
      expect(m.memberId).toEqual(expect.any(String))
    }
  })
})
