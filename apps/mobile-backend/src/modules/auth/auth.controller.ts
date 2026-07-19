import { Router } from "express"
import bcrypt from "bcryptjs"
import crypto, { randomUUID } from "node:crypto"
import { loginSchema, profileSelectSchema, changePasswordSchema, forgotPasswordSchema, resetPasswordSchema } from "@aapli/validation"
import { SOCIETY_ADMIN_ROLES, OCCUPANCY_TYPES } from "@aapli/constants"
import { signAccess, signRefresh, verifyRefresh, refreshExpiresAt } from "../../lib/jwt.js"
import { User, RefreshToken, Member, Society } from "../../models/index.js"
import { requireAuth, requireAuthAllowPending, requireRoles } from "../../middleware/auth.js"
import { loginLimiter, forgotPasswordLimiter, resetPasswordLimiter } from "../../middleware/rateLimit.js"
import { sendEmail, resetCodeEmailHtml } from "../../lib/brevo.js"

export const authRouter: Router = Router()

function sha256(value: string): string {
  return crypto.createHash("sha256").update(value).digest("hex")
}

const RESET_CODE_TTL_MS = 10 * 60 * 1000
const RESET_MAX_ATTEMPTS = 5

// Unified role-aware login for Member + Security + Admin staff
authRouter.post("/login", loginLimiter, async (req, res) => {
  const parsed = loginSchema.safeParse(req.body)
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() })
  const { identifier, password } = parsed.data

  const user = await User.findOne({
    $or: [{ username: identifier }, { email: identifier }],
  })
  if (!user || (user as any).isActive === false) return res.status(401).json({ error: "Invalid credentials" })
  const storedHash = (user as any).passwordHash ?? (user as any).password
  const ok = storedHash && (await bcrypt.compare(password, storedHash))
  if (!ok) return res.status(401).json({ error: "Invalid credentials" })

  const profiles = (user.profiles as any[]) ?? []

  // Multiple society profiles -> ask client to pick one
  if (profiles.length > 1 && !user.activeProfileId) {
    const selectToken = signAccess({ userId: String(user._id), role: user.role, pending: true } as any)
    return res.json({
      needsProfileSelect: true,
      selectToken,
      profiles: profiles.map((p: any) => ({
        profileId: String(p._id), societyName: p.societyName, flatNo: p.flatNo,
      })),
    })
  }

  const profile = profiles.find((p: any) => String(p._id) === String(user.activeProfileId))
    ?? profiles[0]
    ?? { societyId: (user as any).societyId, memberId: (user as any).memberId, role: user.role, status: "Active" }
  return res.json(await issueTokens(user, profile))
})

authRouter.post("/switch-profile", requireAuthAllowPending, async (req, res) => {
  const parsed = profileSelectSchema.safeParse(req.body)
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() })
  const user = await User.findById(req.auth!.userId)
  if (!user) return res.status(404).json({ error: "User not found" })
  const profile = user.profiles.find((p: any) => String(p._id) === parsed.data.profileId)
  if (!profile) return res.status(404).json({ error: "Profile not found" })
  user.activeProfileId = (profile as any)._id
  await user.save()
  return res.json(await issueTokens(user, profile))
})

authRouter.post("/refresh", async (req, res) => {
  const token = req.body?.refreshToken as string | undefined
  if (!token) return res.status(400).json({ error: "No refreshToken" })
  try {
    const { userId, jti } = verifyRefresh(token)
    const stored = await RefreshToken.findOne({ jti, revoked: false })
    if (!stored) return res.status(401).json({ error: "Refresh revoked" })
    stored.revoked = true; await stored.save() // rotate
    const user = await User.findById(userId)
    if (!user) return res.status(401).json({ error: "User gone" })
    const profile = user.profiles.find((p: any) => String(p._id) === String(user.activeProfileId)) ?? user.profiles[0]
    return res.json(await issueTokens(user, profile))
  } catch {
    return res.status(401).json({ error: "Invalid refresh" })
  }
})

authRouter.get("/me", requireAuth, async (req, res) => {
  const user = await User.findById(req.auth!.userId)
    .select("-passwordHash -password -resetCodeHash -resetCodeExpiresAt -resetCodeAttempts")
    .lean()
  if (!user) return res.status(404).json({ error: "User not found" })

  const [memberDoc, societyDoc] = await Promise.all([
    req.auth!.memberId ? Member.findById(req.auth!.memberId).lean() : null,
    req.auth!.societyId ? Society.findById(req.auth!.societyId).lean() : null,
  ])

  return res.json({
    user: { ...user, member: toMemberDto(memberDoc), society: toSocietyDto(societyDoc) },
    claims: req.auth,
  })
})

// Never spread a raw Member doc into an API response — it carries PAN,
// Aadhaar, banking, and history fields (see mongo_export/members.json)
// that have no business leaving the server. Only these fields are safe.
function toMemberDto(m: any) {
  if (!m) return null
  return {
    _id: String(m._id),
    ownerName: m.ownerName ?? null,
    flatNo: m.flatNo ?? null,
    wing: m.wing ?? null,
    flatType: m.flatType ?? null,
    ownershipType: m.ownershipType ?? null,
    carpetAreaSqft: m.carpetAreaSqft ?? null,
    builtUpAreaSqft: m.builtUpAreaSqft ?? null,
    hasVotingRights: m.hasVotingRights ?? null,
    contactNumber: m.contactNumber ?? null,
    whatsappNumber: m.whatsappNumber ?? null,
    parkingSlots: Array.isArray(m.parkingSlots)
      ? m.parkingSlots.map((p: any) => ({ slotNumber: p.slotNumber ?? null, type: p.type ?? null, vehicleType: p.vehicleType ?? null }))
      : [],
    familyMembers: Array.isArray(m.familyMembers)
      ? m.familyMembers.map((f: any) => ({ name: f.name ?? null, relation: f.relation ?? null, age: f.age ?? null }))
      : [],
  }
}

function toSocietyDto(s: any) {
  if (!s) return null
  return { _id: String(s._id), name: s.name ?? null, address: s.address ?? null }
}

authRouter.post("/change-password", requireAuth, async (req, res) => {
  const parsed = changePasswordSchema.safeParse(req.body)
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() })
  const user = await User.findById(req.auth!.userId)
  if (!user) return res.status(404).json({ error: "User not found" })
  const storedHash = (user as any).passwordHash ?? (user as any).password
  const ok = storedHash && (await bcrypt.compare(parsed.data.currentPassword, storedHash))
  if (!ok) return res.status(401).json({ error: "Current password is incorrect" })
  // Write BOTH fields: the web app's login only ever reads `password`, never
  // `passwordHash` — if we only set passwordHash here, a password changed via
  // mobile silently stops working on the web app (web keeps honoring the old
  // `password` value forever). Keeping both in sync avoids touching web's
  // login route at all while closing that split-credential hole.
  const newHash = await bcrypt.hash(parsed.data.newPassword, 10)
  ;(user as any).passwordHash = newHash
  ;(user as any).password = newHash
  ;(user as any).mustChangePassword = false
  await user.save()
  return res.json({ ok: true })
})

authRouter.post("/forgot-password", forgotPasswordLimiter, async (req, res) => {
  const parsed = forgotPasswordSchema.safeParse(req.body)
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() })
  const identifier = parsed.data.identifier

  // Always respond 200 regardless of whether the account exists, is active,
  // or has an email on file — a distinguishable response here (404 vs 400 vs
  // 200) lets an attacker enumerate valid usernames/emails, unlike /login
  // which already collapses "wrong password" and "unknown identifier" into
  // the same 401. Only actually send an email when there's somewhere to
  // send it; the caller can't tell the difference either way.
  const user = await User.findOne({ $or: [{ username: identifier }, { email: identifier }] })
  const email = (user as any)?.email as string | undefined
  if (user && (user as any).isActive !== false && email) {
    const code = String(crypto.randomInt(0, 1_000_000)).padStart(6, "0")
    ;(user as any).resetCodeHash = sha256(code)
    ;(user as any).resetCodeExpiresAt = new Date(Date.now() + RESET_CODE_TTL_MS)
    ;(user as any).resetCodeAttempts = 0
    await user.save()
    await sendEmail({ to: email, subject: "Your AapliSocietyy password reset code", html: resetCodeEmailHtml(code) })
  }
  return res.json({ ok: true })
})

authRouter.post("/reset-password", resetPasswordLimiter, async (req, res) => {
  const parsed = resetPasswordSchema.safeParse(req.body)
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() })
  const { identifier, code, newPassword } = parsed.data

  // Same generic-response principle as /forgot-password: unknown identifier,
  // expired/never-requested code, and wrong code all return the identical
  // 400 below, so none of those cases is distinguishable from the others.
  const invalidCodeResponse = () => res.status(400).json({ error: "Code expired or invalid, request a new one" })

  const user = await User.findOne({ $or: [{ username: identifier }, { email: identifier }] })
  if (!user || (user as any).isActive === false) return invalidCodeResponse()

  const resetCodeHash = (user as any).resetCodeHash as string | undefined
  const resetCodeExpiresAt = (user as any).resetCodeExpiresAt as Date | undefined
  const attempts = ((user as any).resetCodeAttempts as number | undefined) ?? 0
  if (!resetCodeHash || !resetCodeExpiresAt || resetCodeExpiresAt < new Date() || attempts >= RESET_MAX_ATTEMPTS) {
    return invalidCodeResponse()
  }

  if (sha256(code) !== resetCodeHash) {
    ;(user as any).resetCodeAttempts = attempts + 1
    await user.save()
    return invalidCodeResponse()
  }

  const newHash = await bcrypt.hash(newPassword, 10)
  ;(user as any).passwordHash = newHash
  ;(user as any).password = newHash
  ;(user as any).mustChangePassword = false
  ;(user as any).resetCodeHash = undefined
  ;(user as any).resetCodeExpiresAt = undefined
  ;(user as any).resetCodeAttempts = 0
  await user.save()

  await RefreshToken.updateMany({ userId: user._id, revoked: false }, { revoked: true })
  return res.json({ ok: true })
})

// Admin/Secretary looks up members in their society (e.g. to raise a bill by flat number)
authRouter.get("/members", requireAuth, requireRoles(...SOCIETY_ADMIN_ROLES), async (req, res) => {
  const users = await User.find({ societyId: req.auth!.societyId, role: "Member" }).select("username profiles")
  const list = users.flatMap((u: any) =>
    u.profiles
      .filter((p: any) => String(p.societyId) === String(req.auth!.societyId))
      .map((p: any) => ({ memberId: String(p.memberId), username: u.username, flatNo: p.flatNo, wing: p.wing })),
  )
  return res.json(list)
})

async function issueTokens(user: any, profile: any) {
  const jti = randomUUID()
  const refreshToken = signRefresh({ userId: String(user._id), jti })
  await RefreshToken.create({ userId: user._id, jti, expiresAt: refreshExpiresAt(refreshToken) })
  const claims = {
    userId: String(user._id),
    role: profile?.role ?? user.role,
    // Guard each field individually, not just `profile` truthiness: a
    // Staff/Security account with no profiles[] falls back to a plain
    // object with no _id and often no memberId. String(undefined) returns
    // the literal string "undefined" (truthy!), which downstream routes
    // (e.g. /auth/me's Member.findById(req.auth.memberId)) then pass to
    // Mongoose as if it were a real ObjectId, crashing with a CastError.
    societyId: profile?.societyId ? String(profile.societyId) : undefined,
    memberId: profile?.memberId ? String(profile.memberId) : undefined,
    activeProfileId: profile?._id ? String(profile._id) : undefined,
    occupancyType: profile?.occupancyType ?? OCCUPANCY_TYPES.OWNER,
    mustChangePassword: (user as any).mustChangePassword === true || undefined,
  }
  return {
    role: claims.role,
    mustChangePassword: claims.mustChangePassword,
    tokens: { accessToken: signAccess(claims as any), refreshToken },
  }
}
