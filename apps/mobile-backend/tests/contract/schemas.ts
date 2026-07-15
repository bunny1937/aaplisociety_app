import { z } from "zod"

// Real API-response contract schemas (not request/input schemas — those
// already live in packages/shared-validation/src/schemas.ts).
//
// These describe the EXACT shape of what a route actually sends back over
// the wire, based on:
//   - src/models/index.ts (Mongoose schemas -> what toJSON serializes)
//   - the route handlers in src/modules/**/*.controller.ts
//
// Where a shape is a plain literal object built by hand in the controller
// (e.g. login/me/needsProfileSelect), we use .strict() so an accidental
// extra/renamed/removed field fails the test — this is the whole point of
// a contract test vs. the existing field-by-field spot checks in tests/api.
// Where the shape is a raw Mongoose document (Bill/Visitor/Complaint/Notice),
// we also use .strict() listing every schema path + the standard Mongoose
// document fields (_id, createdAt, updatedAt, __v) so the mongo schema and
// the contract schema must be kept in sync by hand — a real regression tool.

export const objectIdString = z
  .string()
  .regex(/^[0-9a-fA-F]{24}$/, "expected a 24-char hex ObjectId string")

export const isoDateString = z.string().datetime()

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------

export const authTokensSchema = z.object({
  accessToken: z.string().min(1),
  refreshToken: z.string().min(1),
})

// POST /v1/auth/login (single-profile / switch-profile / refresh success shape)
export const loginSuccessSchema = z
  .object({
    role: z.string().min(1),
    tokens: authTokensSchema,
  })
  .strict()

// POST /v1/auth/login (multi-profile, no activeProfileId yet)
export const needsProfileSelectSchema = z
  .object({
    needsProfileSelect: z.literal(true),
    selectToken: z.string().min(1),
    profiles: z.array(
      z
        .object({
          profileId: z.string().min(1),
          societyName: z.string(),
          flatNo: z.string(),
        })
        .strict(),
    ),
  })
  .strict()

// A single embedded profile subdocument as returned inside GET /auth/me's user.
export const memberProfileSchema = z
  .object({
    _id: objectIdString,
    memberId: objectIdString.optional(),
    societyId: objectIdString.optional(),
    role: z.string(),
    flatNo: z.string().optional(),
    wing: z.string().optional(),
    societyName: z.string().optional(),
    status: z.string().optional(),
  })
  .strict()

// Safe, hand-picked Member fields as returned inside GET /auth/me's user.
// Mirrors toMemberDto() in src/modules/auth/auth.controller.ts — must NEVER
// carry PAN/Aadhaar/banking/history fields from the raw Member document.
const memberDtoSchema = z
  .object({
    _id: objectIdString,
    ownerName: z.string().nullable(),
    flatNo: z.string().nullable(),
    wing: z.string().nullable(),
    flatType: z.string().nullable(),
    ownershipType: z.string().nullable(),
    carpetAreaSqft: z.number().nullable(),
    builtUpAreaSqft: z.number().nullable(),
    hasVotingRights: z.boolean().nullable(),
    contactNumber: z.string().nullable(),
    whatsappNumber: z.string().nullable(),
    parkingSlots: z.array(
      z.object({
        slotNumber: z.string().nullable(),
        type: z.string().nullable(),
        vehicleType: z.string().nullable(),
      }).strict(),
    ),
    familyMembers: z.array(
      z.object({
        name: z.string().nullable(),
        relation: z.string().nullable(),
        age: z.number().nullable(),
      }).strict(),
    ),
  })
  .strict()
  .nullable()

// Safe, hand-picked Society fields as returned inside GET /auth/me's user.
// Mirrors toSocietyDto() in src/modules/auth/auth.controller.ts.
const societyDtoSchema = z
  .object({
    _id: objectIdString,
    name: z.string().nullable(),
    address: z.string().nullable(),
  })
  .strict()
  .nullable()

// GET /v1/auth/me -> { user, claims }
// `user` must NEVER contain passwordHash. Because this is .strict() and
// passwordHash is intentionally absent from the field list below, a future
// regression that stops excluding it (e.g. dropping .select("-passwordHash"))
// will make safeParse fail on the unrecognized "passwordHash" key — not just
// a manual `.not.toHaveProperty` check.
export const meUserSchema = z
  .object({
    _id: objectIdString,
    username: z.string(),
    email: z.string().optional(),
    role: z.string(),
    societyId: objectIdString.optional(),
    memberId: objectIdString.optional(),
    profiles: z.array(memberProfileSchema),
    activeProfileId: objectIdString.optional(),
    isActive: z.boolean(),
    mustChangePassword: z.boolean(),
    createdAt: isoDateString,
    updatedAt: isoDateString,
    __v: z.number(),
    member: memberDtoSchema,
    society: societyDtoSchema,
  })
  .strict()

// The decoded JWT payload (jsonwebtoken adds iat/exp on top of our claims;
// we don't lock those to .strict() since they're library-injected, not
// something our own route code controls the exact shape of — but every
// field our app actually relies on IS required here).
export const meClaimsSchema = z
  .object({
    userId: objectIdString,
    role: z.string(),
    societyId: objectIdString.optional(),
    memberId: objectIdString.optional(),
    activeProfileId: objectIdString.optional(),
    iat: z.number().optional(),
    exp: z.number().optional(),
  })
  .passthrough()

export const meResponseSchema = z
  .object({
    user: meUserSchema,
    claims: meClaimsSchema,
  })
  .strict()

// ---------------------------------------------------------------------------
// Bills
// ---------------------------------------------------------------------------

export const billItemSchema = z
  .object({
    _id: objectIdString,
    societyId: objectIdString,
    memberId: objectIdString,
    period: z.string().optional(),
    title: z.string().optional(),
    principal: z.number(),
    interest: z.number(),
    amount: z.number(),
    amountPaid: z.number(),
    status: z.enum(["Unpaid", "Partial", "Paid"]),
    dueDate: isoDateString.nullable(),
    periodLabel: z.string(),
    ownerName: z.string().nullable(),
    flatNo: z.string().nullable(),
    wing: z.string().nullable(),
    areaSqft: z.number().nullable(),
    billHtml: z.string(),
    createdAt: isoDateString,
    updatedAt: isoDateString,
    __v: z.number(),
  })
  .strict()

// ---------------------------------------------------------------------------
// Visitors
// ---------------------------------------------------------------------------

export const visitorItemSchema = z
  .object({
    _id: objectIdString,
    societyId: objectIdString,
    memberId: objectIdString.optional(),
    name: z.string(),
    phone: z.string(),
    photoKey: z.string().optional(),
    vehicleNumber: z.string().optional(),
    purpose: z.string().optional(),
    status: z.enum(["Pending", "Approved", "Rejected", "Entered", "Exited"]),
    escalationLevel: z.number(),
    approvedBy: objectIdString.optional(),
    enteredAt: isoDateString.optional(),
    exitedAt: isoDateString.optional(),
    createdAt: isoDateString,
    updatedAt: isoDateString,
    __v: z.number(),
  })
  .strict()

// ---------------------------------------------------------------------------
// Complaints
// ---------------------------------------------------------------------------

export const complaintItemSchema = z
  .object({
    _id: objectIdString,
    societyId: objectIdString,
    memberId: objectIdString.optional(),
    category: z.enum(["noise", "parking", "water", "security", "maintenance", "other"]),
    title: z.string(),
    description: z.string().optional(),
    status: z.enum(["Open", "In progress", "Resolved", "Rejected"]),
    anonymous: z.boolean(),
    resolutionNote: z.string().optional(),
    createdAt: isoDateString,
    updatedAt: isoDateString,
    __v: z.number(),
  })
  .strict()

// ---------------------------------------------------------------------------
// Notices
// ---------------------------------------------------------------------------

export const noticeItemSchema = z
  .object({
    _id: objectIdString,
    societyId: objectIdString,
    title: z.string(),
    body: z.string().optional(),
    tag: z.enum(["General", "Urgent", "Event", "Community", "Maintenance"]),
    postedBy: objectIdString.optional(),
    pinned: z.boolean(),
    createdAt: isoDateString,
    updatedAt: isoDateString,
    __v: z.number(),
  })
  .strict()
