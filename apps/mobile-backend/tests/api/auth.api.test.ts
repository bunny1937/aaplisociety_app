import { describe, it, expect } from "vitest"
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

const app = createApp()
const PASSWORD = "Passw0rd!"

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
      flatNo: "A-101", wing: "A", societyName: "Sunrise CHS", status: "active",
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
        { societyId: societyId1, memberId: randomObjectId(), role: ROLES.MEMBER, flatNo: "A-101", wing: "A", societyName: "Sunrise CHS", status: "active" },
        { societyId: societyId2, memberId: randomObjectId(), role: ROLES.MEMBER, flatNo: "B-202", wing: "B", societyName: "Palm Residency", status: "active" },
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
        { societyId: societyId1, memberId: randomObjectId(), role: ROLES.MEMBER, flatNo: "A-101", wing: "A", societyName: "Sunrise CHS", status: "active" },
        { societyId: societyId2, memberId: randomObjectId(), role: ROLES.MEMBER, flatNo: "B-202", wing: "B", societyName: "Palm Residency", status: "active" },
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

describe("POST /v1/auth/add-member and GET /v1/auth/members", () => {
  async function createAdmin() {
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
        flatNo: "Office", wing: "", societyName: "Test Society", status: "active",
      }],
      isActive: true,
    })
    const profile = admin.profiles[0] as any
    const token = bearerToken({
      userId: String(admin._id),
      role: ROLES.ADMIN,
      societyId: String(adminSocietyId),
      memberId: String(profile.memberId),
      activeProfileId: String(profile._id),
    })
    return { admin, adminSocietyId, token }
  }

  it("rejects add-member for a non-admin role with 403", async () => {
    const token = bearerToken({ role: ROLES.MEMBER })
    const res = await request(app).post("/v1/auth/add-member").set(authHeader(token)).send({
      username: "new.member", flatNo: "C-303",
    })
    expect(res.status).toBe(403)
    expect(res.body).toEqual({ error: "Forbidden" })
  })

  it("creates a member as Admin, returns a tempPassword that actually logs in, and rejects duplicate usernames", async () => {
    const { token } = await createAdmin()
    const username = `new.member.${Math.floor(Math.random() * 1e6)}`

    const createRes = await request(app).post("/v1/auth/add-member").set(authHeader(token)).send({
      username, flatNo: "C-303", role: "Member",
    })
    expect(createRes.status).toBe(201)
    expect(createRes.body.username).toBe(username)
    expect(createRes.body.tempPassword).toEqual(expect.any(String))
    expect(createRes.body.tempPassword.length).toBeGreaterThan(0)

    const loginRes = await request(app).post("/v1/auth/login").send({
      identifier: username, password: createRes.body.tempPassword,
    })
    expect(loginRes.status).toBe(200)
    expect(loginRes.body.tokens.accessToken).toEqual(expect.any(String))

    const dupRes = await request(app).post("/v1/auth/add-member").set(authHeader(token)).send({
      username, flatNo: "C-304",
    })
    expect(dupRes.status).toBe(409)
    expect(dupRes.body).toEqual({ error: "Username already taken" })
  })

  it("rejects GET /auth/members for a non-admin role with 403", async () => {
    const token = bearerToken({ role: ROLES.SECURITY })
    const res = await request(app).get("/v1/auth/members").set(authHeader(token))
    expect(res.status).toBe(403)
    expect(res.body).toEqual({ error: "Forbidden" })
  })

  it("critical: a newly added member must change their temp password before using any other route", async () => {
    const { token: adminToken } = await createAdmin()
    const username = `forced.${Math.floor(Math.random() * 1e6)}`
    const createRes = await request(app).post("/v1/auth/add-member").set(authHeader(adminToken)).send({
      username, flatNo: "D-1",
    })

    const loginRes = await request(app).post("/v1/auth/login").send({
      identifier: username, password: createRes.body.tempPassword,
    })
    expect(loginRes.body.mustChangePassword).toBe(true)
    const restrictedToken = loginRes.body.tokens.accessToken as string

    const blocked = await request(app).get("/v1/notices").set(authHeader(restrictedToken))
    expect(blocked.status).toBe(403)
    expect(blocked.body).toEqual({ error: "Password change required" })

    const meStillWorks = await request(app).get("/v1/auth/me").set(authHeader(restrictedToken))
    expect(meStillWorks.status).toBe(200)

    const changeRes = await request(app)
      .post("/v1/auth/change-password")
      .set(authHeader(restrictedToken))
      .send({ currentPassword: createRes.body.tempPassword, newPassword: "NewPassw0rd!" })
    expect(changeRes.status).toBe(200)

    const reLogin = await request(app).post("/v1/auth/login").send({
      identifier: username, password: "NewPassw0rd!",
    })
    expect(reLogin.body.mustChangePassword).toBeFalsy()

    const unblocked = await request(app).get("/v1/notices").set(authHeader(reLogin.body.tokens.accessToken))
    expect(unblocked.status).toBe(200)
  })

  it("returns the list of members in the admin's society", async () => {
    const { token, adminSocietyId } = await createAdmin()
    const usernameA = `member.a.${Math.floor(Math.random() * 1e6)}`
    const usernameB = `member.b.${Math.floor(Math.random() * 1e6)}`
    await request(app).post("/v1/auth/add-member").set(authHeader(token)).send({ username: usernameA, flatNo: "A-1" })
    await request(app).post("/v1/auth/add-member").set(authHeader(token)).send({ username: usernameB, flatNo: "A-2" })

    const res = await request(app).get("/v1/auth/members").set(authHeader(token))
    expect(res.status).toBe(200)
    expect(Array.isArray(res.body)).toBe(true)
    expect(res.body).toHaveLength(2)
    const usernames = res.body.map((m: any) => m.username).sort()
    expect(usernames).toEqual([usernameA, usernameB].sort())
    for (const m of res.body) {
      expect(m.flatNo).toEqual(expect.any(String))
      expect(m.memberId).toEqual(expect.any(String))
    }
  })
})
