# Member Data Wiring + UI Fill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Kill every "null" / raw-username / "Not available yet" placeholder visible in the Pulse member surface (Home, Bills, Bill detail/format, Profile, Ledger, Receipts) by wiring the app to data that already exists in MongoDB but was never modeled or exposed by `apps/mobile-backend`, and by building the two backend endpoints (Ledger, Receipts) that were previously derived client-side as approximations.

**Architecture:** `apps/mobile-backend/src/models/index.ts` currently only models a slice of the real database (the real `members`, `societies`, `transactions`, `receipts` collections have no Mongoose model at all, so `.lean()` reads of `Bill` pass their extra real fields through by accident while non-modeled collections are invisible to the API entirely). This plan adds `Member`, `Society`, `Transaction`, `Receipt` models (read-heavy, `strict:false`, always queried with `.lean()`), threads them into `GET /auth/me` (member+society), `GET /bills` (owner/flat/area enrichment + a reliable `periodLabel`), two new endpoints `GET /ledger` and `GET /receipts`, and extends `POST /bills/:id/pay` to also write a `Transaction` + `Receipt` so payments made through the app show up immediately in both. On the Flutter side, every screen that read `bill['title']`/`user['username']` as a stand-in switches to the new server-provided fields, Profile grows real list UI for parking slots and family members instead of a single flat placeholder row, and "Save PDF"/"Share" on bills and receipts produce a real PDF via the `printing`/`pdf` packages instead of toasting.

**Tech Stack:** Express + Mongoose + Zod + Vitest + supertest + `mongodb-memory-server` (backend, `apps/mobile-backend`); Flutter + `flutter_bloc` + `dio` + `printing`/`pdf` (frontend, `apps/mobile-app`).

## Global Constraints

- Never add a Mongoose schema field for data the client shouldn't see — `Member` has `panCard`, `aadhaar`, `securityDeposit`, `openingBalance` etc. in the real DB; the `/auth/me` and `/bills` DTOs must only project the specific safe fields listed in each task, never spread a raw Member/Society doc into a response.
- Every new/changed Mongoose query in this plan must use `.lean()` — matches the existing `Bill.find(...).lean()` pattern in `bill.controller.ts` and is required for `strict:false` schemas to pass through real-DB fields not explicitly declared.
- Every new backend route must go through `requireAuth, withTenant` (see `apps/mobile-backend/src/middleware/tenancy.ts`) and filter by `req.auth!.memberId` for non-admin roles, `req.auth!.societyId` always — same tenancy rule as `bill.controller.ts`.
- No fabricated data: fields with no backing source (e.g. Profile's "Emergency contact") stay `null`/"Not available yet" — do not invent placeholder values.
- Backend coverage thresholds are enforced by `vitest.config.ts` (`lines: 58, statements: 58, functions: 48, branches: 65` — run `npm run test:coverage` in `apps/mobile-backend` if unsure a task keeps the suite green).
- Follow existing test conventions exactly: factories in `tests/factories/*.factory.ts` re-exported from `tests/factories/index.ts`, `bearerToken()`/`authHeader()` from `tests/helpers/auth.ts`, `randomObjectId()` from `tests/utils/randomObjectId.ts`.

---

## File Structure

**Backend — create:**
- `apps/mobile-backend/src/lib/periodLabel.ts` — shared `periodLabelFrom()` used by bills, receipts, ledger.
- `apps/mobile-backend/src/modules/ledger/ledger.controller.ts` — `GET /v1/ledger`.
- `apps/mobile-backend/src/modules/receipts/receipt.controller.ts` — `GET /v1/receipts`.
- `apps/mobile-backend/tests/factories/member.factory.ts`, `society.factory.ts`, `transaction.factory.ts`, `receipt.factory.ts`.
- `apps/mobile-backend/tests/api/ledger.api.test.ts`, `receipts.api.test.ts`.

**Backend — modify:**
- `apps/mobile-backend/src/models/index.ts` — add `Member`, `Society`, `Transaction`, `Receipt` schemas/models.
- `apps/mobile-backend/src/modules/auth/auth.controller.ts` — `GET /me` attaches `member`+`society`.
- `apps/mobile-backend/src/modules/bills/bill.controller.ts` — `normalizeBill()` enrichment, `POST /:id/pay` writes `Transaction`+`Receipt`.
- `apps/mobile-backend/src/app.ts` — mount `ledgerRouter`, `receiptRouter`.
- `apps/mobile-backend/tests/factories/index.ts` — re-export new factories.
- `apps/mobile-backend/tests/api/auth.api.test.ts`, `bills.api.test.ts` — new assertions.

**Frontend — create:**
- `apps/mobile-app/lib/features/member/pulse/member_display.dart` — `resolveDisplayName()`/`resolveSocietyName()` pure helpers.
- `apps/mobile-app/lib/features/member/pulse/bill_pdf.dart` — `renderBillPdf()`/`renderReceiptPdf()` PDF builders.
- `apps/mobile-app/test/unit/member_display_test.dart`, `bill_title_test.dart`.

**Frontend — modify:**
- `apps/mobile-app/pubspec.yaml` — add `printing`, `pdf` dependencies.
- `apps/mobile-app/lib/features/member/bills_page.dart` — `billTitle()` helper, fix "null" call site.
- `apps/mobile-app/lib/features/member/dashboard_page.dart` — real display name + society label.
- `apps/mobile-app/lib/features/member/member_profile_page.dart` — real fields + parking/family list UI.
- `apps/mobile-app/lib/features/member/pulse/bill_detail_sheet.dart` — `billTitle()`, real PDF Save/Share.
- `apps/mobile-app/lib/features/member/pulse/bill_format_sheet.dart` — real Owner/Flat/Area/Society, real PDF.
- `apps/mobile-app/lib/features/member/ledger_page.dart` — rewrite to `GET /ledger`.
- `apps/mobile-app/lib/features/member/receipts_page.dart` — rewrite to `GET /receipts`, real PDF download.
- `apps/mobile-app/test/fixtures/bill_fixtures.dart`, `auth_fixtures.dart` — add `periodLabel`/`member`/`society`.
- `apps/mobile-app/MEMBER_V2_GAPS.md` — mark resolved gaps.

---

### Task 1: Shared period-label helper (backend)

**Files:**
- Create: `apps/mobile-backend/src/lib/periodLabel.ts`
- Test: `apps/mobile-backend/tests/unit/periodLabel.test.ts`

**Interfaces:**
- Produces: `periodLabelFrom(source: { billPeriodId?: string | null; billYear?: number | null; billMonth?: number | null; title?: string | null; period?: string | null }): string` — used by Tasks 3, 4, 5.

- [ ] **Step 1: Write the failing test**

```typescript
import { describe, it, expect } from "vitest"
import { periodLabelFrom } from "../../src/lib/periodLabel.js"

describe("periodLabelFrom", () => {
  it("formats a billPeriodId (YYYY-MM) as 'Mon YYYY'", () => {
    expect(periodLabelFrom({ billPeriodId: "2026-05" })).toBe("May 2026")
  })

  it("falls back to billYear/billMonth when billPeriodId is absent", () => {
    expect(periodLabelFrom({ billYear: 2026, billMonth: 4 })).toBe("Apr 2026")
  })

  it("prefers billPeriodId over billYear/billMonth when both present", () => {
    expect(periodLabelFrom({ billPeriodId: "2026-05", billYear: 2026, billMonth: 4 })).toBe("May 2026")
  })

  it("falls back to title, then period, then 'Bill' when no period fields exist", () => {
    expect(periodLabelFrom({ title: "Q2 Maintenance" })).toBe("Q2 Maintenance")
    expect(periodLabelFrom({ period: "2026-Q2" })).toBe("2026-Q2")
    expect(periodLabelFrom({})).toBe("Bill")
  })

  it("ignores a malformed billPeriodId instead of throwing", () => {
    expect(periodLabelFrom({ billPeriodId: "not-a-period", period: "2026-Q2" })).toBe("2026-Q2")
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run (from `apps/mobile-backend`): `npx vitest run tests/unit/periodLabel.test.ts`
Expected: FAIL — `Cannot find module '../../src/lib/periodLabel.js'`

- [ ] **Step 3: Write minimal implementation**

```typescript
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

interface PeriodSource {
  billPeriodId?: string | null
  billYear?: number | null
  billMonth?: number | null
  title?: string | null
  period?: string | null
}

// Bills/receipts/transactions imported from different eras carry different
// period fields (billPeriodId "YYYY-MM" vs billYear+billMonth vs a free-text
// title/period string on hand-created records) — this gives every caller one
// human-readable label regardless of source, instead of each screen doing
// its own `bill['title'] ?? bill['period']` fallback chain (which produces
// literal "null" text when both are actually absent).
export function periodLabelFrom(source: PeriodSource): string {
  if (source.billPeriodId && /^\d{4}-\d{2}$/.test(source.billPeriodId)) {
    const [year, month] = source.billPeriodId.split("-").map(Number)
    if (month >= 1 && month <= 12) return `${MONTHS[month - 1]} ${year}`
  }
  if (source.billYear && source.billMonth && source.billMonth >= 1 && source.billMonth <= 12) {
    return `${MONTHS[source.billMonth - 1]} ${source.billYear}`
  }
  return source.title ?? source.period ?? "Bill"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run tests/unit/periodLabel.test.ts`
Expected: PASS (5 tests)

- [ ] **Step 5: Commit**

```bash
git add apps/mobile-backend/src/lib/periodLabel.ts apps/mobile-backend/tests/unit/periodLabel.test.ts
git commit -m "feat(backend): add shared periodLabelFrom helper"
```

---

### Task 2: Member, Society, Transaction, Receipt models

**Files:**
- Modify: `apps/mobile-backend/src/models/index.ts`
- Create: `apps/mobile-backend/tests/factories/member.factory.ts`
- Create: `apps/mobile-backend/tests/factories/society.factory.ts`
- Create: `apps/mobile-backend/tests/factories/transaction.factory.ts`
- Create: `apps/mobile-backend/tests/factories/receipt.factory.ts`
- Modify: `apps/mobile-backend/tests/factories/index.ts`
- Test: `apps/mobile-backend/tests/unit/models.test.ts`

**Interfaces:**
- Produces: `Member`, `Society`, `Transaction`, `Receipt` exported from `src/models/index.ts`, all `strict: false`. Field names below match `apps/mobile-backend/mongo_export/{members,societies,transactions,receipts}.json` exactly.
- Produces: `makeMember(overrides)`, `makeSociety(overrides)`, `makeTransaction(overrides)`, `makeReceipt(overrides)` from `tests/factories/index.js`.

- [ ] **Step 1: Write the failing test**

```typescript
import { describe, it, expect } from "vitest"
import { Member, Society, Transaction, Receipt } from "../../src/models/index.js"
import { makeMember, makeSociety, makeTransaction, makeReceipt } from "../factories/index.js"

describe("Member/Society/Transaction/Receipt models", () => {
  it("persists and reads back a Member with nested parkingSlots/familyMembers", async () => {
    const doc = await Member.create(makeMember({ ownerName: "Tanvi Bansal", flatType: "4BHK" }))
    const found = await Member.findById(doc._id).lean()
    expect(found!.ownerName).toBe("Tanvi Bansal")
    expect(found!.flatType).toBe("4BHK")
    expect((found as any).parkingSlots).toHaveLength(1)
    expect((found as any).parkingSlots[0].slotNumber).toBe("P-B-112")
    expect((found as any).familyMembers).toHaveLength(1)
    expect((found as any).familyMembers[0].name).toBe("Neha Sharma")
  })

  it("persists and reads back a Society", async () => {
    const doc = await Society.create(makeSociety({ name: "Sunrise Complex" }))
    const found = await Society.findById(doc._id).lean()
    expect(found!.name).toBe("Sunrise Complex")
  })

  it("persists and reads back a Transaction", async () => {
    const doc = await Transaction.create(makeTransaction({ type: "Credit", amount: 594.25 }))
    const found = await Transaction.findById(doc._id).lean()
    expect(found!.type).toBe("Credit")
    expect(found!.amount).toBe(594.25)
  })

  it("persists and reads back a Receipt", async () => {
    const doc = await Receipt.create(makeReceipt({ receiptNo: "RCP-TEST-0001" }))
    const found = await Receipt.findById(doc._id).lean()
    expect(found!.receiptNo).toBe("RCP-TEST-0001")
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run tests/unit/models.test.ts`
Expected: FAIL — `Member is not exported` (or similar) since the models/factories don't exist yet.

- [ ] **Step 3: Write minimal implementation**

Append to `apps/mobile-backend/src/models/index.ts` (before the `export const User = ...` block, so exports at the bottom can reference them):

```typescript
const ParkingSlotSchema = new Schema({
  slotNumber: String,
  type: String,
  vehicleType: String,
  monthlyBilling: Boolean,
}, { _id: false })

const FamilyMemberSchema = new Schema({
  name: String,
  relation: String,
  age: Number,
  contactNumber: String,
  occupation: String,
}, { _id: false })

// Mirrors the real `members` collection (see
// apps/mobile-backend/mongo_export/members.json) — richer than the app has
// ever surfaced. `strict: false` + always-`.lean()` reads (see
// modules/auth, modules/bills) so fields present in the real DB but not
// declared here (panCard, aadhaar, securityDeposit, ...) don't get silently
// dropped, while DTOs still explicitly project only the safe subset below.
const MemberSchema = new Schema({
  societyId: { type: ObjectId, ref: "Society", index: true },
  userId: { type: ObjectId, ref: "User", index: true },
  flatNo: String,
  wing: String,
  floor: Number,
  carpetAreaSqft: Number,
  builtUpAreaSqft: Number,
  flatType: String,
  parkingSlots: [ParkingSlotSchema],
  isActive: { type: Boolean, default: true },
  ownershipType: String,
  possessionDate: Date,
  ownerName: String,
  contactNumber: String,
  alternateContact: String,
  whatsappNumber: String,
  emailPrimary: String,
  emailSecondary: String,
  familyMembers: [FamilyMemberSchema],
  membershipStatus: String,
  membershipNumber: String,
  hasVotingRights: Boolean,
}, { timestamps: true, strict: false })

// Mirrors the real `societies` collection.
const SocietySchema = new Schema({
  name: String,
  address: String,
  gstNo: String,
  fyStartMonth: Number,
}, { timestamps: true, strict: false })

// Mirrors the real `transactions` collection — the actual member ledger.
const TransactionSchema = new Schema({
  transactionId: String,
  date: Date,
  memberId: { type: ObjectId, ref: "Member", index: true },
  societyId: { type: ObjectId, ref: "Society", required: true, index: true },
  type: { type: String, required: true }, // "Debit" | "Credit"
  category: String,
  description: String,
  amount: { type: Number, required: true },
  balanceAfterTransaction: Number,
  referenceId: ObjectId,
  referenceModel: String,
  billPeriodId: String,
  paymentMode: String,
}, { timestamps: true, strict: false })

// Mirrors the real `receipts` collection.
const ReceiptSchema = new Schema({
  receiptNo: String,
  filename: String,
  billId: { type: ObjectId, ref: "Bill" },
  billPeriodId: String,
  memberId: { type: ObjectId, ref: "Member", index: true },
  societyId: { type: ObjectId, ref: "Society", required: true, index: true },
  amount: { type: Number, required: true },
  paymentMode: String,
  paidAt: Date,
  transactionId: String,
  notes: String,
  status: { type: String, default: "Generated" },
}, { timestamps: true, strict: false })

export const Member = model("Member", MemberSchema)
export const Society = model("Society", SocietySchema)
export const Transaction = model("Transaction", TransactionSchema)
export const Receipt = model("Receipt", ReceiptSchema)
```

Add the four `export const` lines to the existing export block at the bottom (next to `export const User = ...`) rather than duplicating a second block — the snippet above already shows their final `export const` form; place the schema definitions above the existing `export const User = model(...)` line and the four new export lines directly below it.

Create `apps/mobile-backend/tests/factories/member.factory.ts`:

```typescript
import { randomObjectId } from "../utils/randomObjectId.js"

// Plain-object builder matching the MemberSchema shape in src/models/index.ts
// (and the real shape in mongo_export/members.json).
export function makeMember(overrides: Record<string, unknown> = {}) {
  return {
    societyId: randomObjectId(),
    userId: randomObjectId(),
    flatNo: "1001",
    wing: "B",
    floor: 18,
    carpetAreaSqft: 2112,
    builtUpAreaSqft: 2321,
    flatType: "4BHK",
    parkingSlots: [{ slotNumber: "P-B-112", type: "Open", vehicleType: "Two-Wheeler", monthlyBilling: true }],
    isActive: true,
    ownershipType: "Rented",
    possessionDate: new Date("2020-04-07"),
    ownerName: "Tanvi Bansal",
    contactNumber: "9484122592",
    whatsappNumber: "9676248289",
    emailPrimary: "tanvi.bansal770@example.com",
    familyMembers: [{ name: "Neha Sharma", relation: "Spouse", age: 34, occupation: "Housewife" }],
    membershipStatus: "Active",
    membershipNumber: "MEM-0001",
    hasVotingRights: true,
    ...overrides,
  }
}
```

Create `apps/mobile-backend/tests/factories/society.factory.ts`:

```typescript
// Plain-object builder matching the SocietySchema shape in src/models/index.ts.
export function makeSociety(overrides: Record<string, unknown> = {}) {
  return {
    name: "Sunrise Complex",
    address: "456 Park Avenue, Pune, Maharashtra 411001",
    fyStartMonth: 4,
    gstNo: "27FGHIJ5678G2Y6",
    ...overrides,
  }
}
```

Create `apps/mobile-backend/tests/factories/transaction.factory.ts`:

```typescript
import { randomObjectId } from "../utils/randomObjectId.js"

// Plain-object builder matching the TransactionSchema shape in src/models/index.ts.
export function makeTransaction(overrides: Record<string, unknown> = {}) {
  return {
    transactionId: `TXN${Math.floor(Math.random() * 1e10)}`,
    date: new Date("2026-05-14"),
    memberId: randomObjectId(),
    societyId: randomObjectId(),
    type: "Debit",
    category: "Maintenance",
    description: "Bill generated for 2026-05",
    amount: 594.25,
    balanceAfterTransaction: 594.25,
    billPeriodId: "2026-05",
    paymentMode: "System",
    ...overrides,
  }
}
```

Create `apps/mobile-backend/tests/factories/receipt.factory.ts`:

```typescript
import { randomObjectId } from "../utils/randomObjectId.js"

// Plain-object builder matching the ReceiptSchema shape in src/models/index.ts.
export function makeReceipt(overrides: Record<string, unknown> = {}) {
  return {
    receiptNo: `RCP-${Date.now()}`,
    billId: randomObjectId(),
    billPeriodId: "2026-05",
    memberId: randomObjectId(),
    societyId: randomObjectId(),
    amount: 594.25,
    paymentMode: "Cash",
    paidAt: new Date("2026-05-13"),
    transactionId: `TXN${Math.floor(Math.random() * 1e10)}`,
    status: "Generated",
    ...overrides,
  }
}
```

Update `apps/mobile-backend/tests/factories/index.ts`:

```typescript
export { makeUser, hashPassword } from "./user.factory.js"
export { makeBill } from "./bill.factory.js"
export { makeVisitor } from "./visitor.factory.js"
export { makeMember } from "./member.factory.js"
export { makeSociety } from "./society.factory.js"
export { makeTransaction } from "./transaction.factory.js"
export { makeReceipt } from "./receipt.factory.js"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run tests/unit/models.test.ts`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add apps/mobile-backend/src/models/index.ts apps/mobile-backend/tests/factories apps/mobile-backend/tests/unit/models.test.ts
git commit -m "feat(backend): add Member/Society/Transaction/Receipt models + factories"
```

---

### Task 3: `GET /v1/auth/me` returns real member + society

**Files:**
- Modify: `apps/mobile-backend/src/modules/auth/auth.controller.ts:75-78`
- Modify: `apps/mobile-backend/tests/api/auth.api.test.ts`

**Interfaces:**
- Consumes: `Member`, `Society` from `../../models/index.js` (Task 2).
- Produces: `GET /v1/auth/me` response `{ user: { ...existing fields, member: MemberDto | null, society: { _id, name, address } | null }, claims }`. `MemberDto` shape consumed by Task 8/9 (Flutter): `{ _id, ownerName, flatNo, wing, flatType, ownershipType, carpetAreaSqft, builtUpAreaSqft, hasVotingRights, contactNumber, whatsappNumber, parkingSlots: [{slotNumber,type,vehicleType}], familyMembers: [{name,relation,age}] }`.

- [ ] **Step 1: Write the failing test**

Add to `apps/mobile-backend/tests/api/auth.api.test.ts` (new imports at top: `Member, Society` from `../../src/models/index.js`, `makeMember, makeSociety` from `../factories/index.js`; append inside the existing `describe("GET /v1/auth/me", ...)` block):

```typescript
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run tests/api/auth.api.test.ts`
Expected: FAIL — `res.body.user.member` is `undefined`, not the expected object.

- [ ] **Step 3: Write minimal implementation**

In `apps/mobile-backend/src/modules/auth/auth.controller.ts`, add the import and replace the `/me` handler:

```typescript
import { User, RefreshToken, Member, Society, Types } from "../../models/index.js"
```

```typescript
authRouter.get("/me", requireAuth, async (req, res) => {
  const user = await User.findById(req.auth!.userId).select("-passwordHash").lean()
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run tests/api/auth.api.test.ts`
Expected: PASS (all tests in the file, including the two new ones and the pre-existing "returns the user (without passwordHash)" test — verify that one still passes since `user` now has extra `member`/`society` keys but no removed keys).

- [ ] **Step 5: Commit**

```bash
git add apps/mobile-backend/src/modules/auth/auth.controller.ts apps/mobile-backend/tests/api/auth.api.test.ts
git commit -m "feat(backend): attach real Member/Society data to GET /auth/me"
```

---

### Task 4: Bill enrichment — periodLabel, owner/flat/area, billHtml fallback

**Files:**
- Modify: `apps/mobile-backend/src/modules/bills/bill.controller.ts`
- Modify: `apps/mobile-backend/tests/api/bills.api.test.ts`

**Interfaces:**
- Consumes: `Member` (Task 2), `periodLabelFrom` (Task 1).
- Produces: every bill object returned by `GET /v1/bills` and `POST /v1/bills/:id/pay` now always has `periodLabel: string`, `ownerName: string|null`, `flatNo: string|null`, `wing: string|null`, `areaSqft: number|null`, `billHtml: string` (never absent). Consumed by Flutter Tasks 7/10/11.

- [ ] **Step 1: Write the failing test**

Add to `apps/mobile-backend/tests/api/bills.api.test.ts` (new imports: `Member` from `../../src/models/index.js`, `makeMember` from `../factories/index.js`; append new `describe` block):

```typescript
describe("GET /v1/bills enrichment", () => {
  it("always includes a non-null periodLabel, even for bills with neither title nor period fields", async () => {
    const societyId = randomObjectId()
    const memberId = randomObjectId()
    await Bill.create({ societyId, memberId, billPeriodId: "2026-05", amount: 442.63, status: "Paid" })
    const token = bearerToken({ role: ROLES.MEMBER, societyId: String(societyId), memberId: String(memberId) })

    const res = await request(app).get("/v1/bills").set(authHeader(token))
    expect(res.status).toBe(200)
    expect(res.body[0].periodLabel).toBe("May 2026")
    expect(res.body[0].periodLabel).not.toBe("null")
  })

  it("enriches each bill with the linked Member's ownerName/flatNo/wing/areaSqft", async () => {
    const societyId = randomObjectId()
    const memberId = randomObjectId()
    await Member.create({ ...makeMember({ ownerName: "Vishal Gupta", flatNo: "1042", wing: "A", carpetAreaSqft: 1500 }), _id: memberId, societyId })
    await Bill.create(makeBill({ societyId, memberId }))
    const token = bearerToken({ role: ROLES.MEMBER, societyId: String(societyId), memberId: String(memberId) })

    const res = await request(app).get("/v1/bills").set(authHeader(token))
    expect(res.status).toBe(200)
    expect(res.body[0].ownerName).toBe("Vishal Gupta")
    expect(res.body[0].flatNo).toBe("1042")
    expect(res.body[0].wing).toBe("A")
    expect(res.body[0].areaSqft).toBe(1500)
  })

  it("returns ownerName/flatNo/wing/areaSqft: null (never throws) when no Member is linked", async () => {
    const societyId = randomObjectId()
    const memberId = randomObjectId()
    await Bill.create(makeBill({ societyId, memberId }))
    const token = bearerToken({ role: ROLES.MEMBER, societyId: String(societyId), memberId: String(memberId) })

    const res = await request(app).get("/v1/bills").set(authHeader(token))
    expect(res.status).toBe(200)
    expect(res.body[0].ownerName).toBeNull()
  })

  it("always includes non-empty billHtml, synthesizing one from charges when the imported bill has none", async () => {
    const societyId = randomObjectId()
    const memberId = randomObjectId()
    await Bill.create({ societyId, memberId, billPeriodId: "2026-05", amount: 240, charges: { "Maintenance Charges": 240 }, status: "Unpaid" })
    const token = bearerToken({ role: ROLES.MEMBER, societyId: String(societyId), memberId: String(memberId) })

    const res = await request(app).get("/v1/bills").set(authHeader(token))
    expect(res.status).toBe(200)
    expect(typeof res.body[0].billHtml).toBe("string")
    expect(res.body[0].billHtml.length).toBeGreaterThan(0)
    expect(res.body[0].billHtml).toContain("Maintenance Charges")
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run tests/api/bills.api.test.ts`
Expected: FAIL — `res.body[0].periodLabel` is `undefined`.

- [ ] **Step 3: Write minimal implementation**

Replace the top of `apps/mobile-backend/src/modules/bills/bill.controller.ts`:

```typescript
import { Router } from "express"
import { paymentSchema, billCreateSchema } from "@aapli/validation"
import { BILL_STATUS, BILLING_WRITE_ROLES } from "@aapli/constants"
import { randomUUID } from "node:crypto"
import { Bill, Payment, Member, Transaction, Receipt } from "../../models/index.js"
import { requireAuth, requireRoles } from "../../middleware/auth.js"
import { withTenant } from "../../middleware/tenancy.js"
import { periodLabelFrom } from "../../lib/periodLabel.js"

export const billRouter = Router()
billRouter.use(requireAuth, withTenant)

// Members see their own bills; admins/secretaries see the whole society
billRouter.get("/", async (req, res) => {
  const isAdmin = BILLING_WRITE_ROLES.includes(req.auth!.role)
  const filter: Record<string, unknown> = { societyId: (req as any).societyId }
  if (!isAdmin) filter.memberId = req.auth!.memberId
  const bills = await Bill.find(filter).sort({ createdAt: -1 }).limit(200).lean()

  const memberIds = [...new Set(bills.map((b: any) => String(b.memberId)))]
  const members = await Member.find({ _id: { $in: memberIds } })
    .select("ownerName flatNo wing carpetAreaSqft")
    .lean()
  const memberById = new Map(members.map((m: any) => [String(m._id), m]))

  return res.json(bills.map((b: any) => normalizeBill(b, memberById.get(String(b.memberId)))))
})

// Older imported bill docs use totalAmount/totalBillDue instead of amount; unify here
// so every client reads one consistent shape regardless of import source.
// `member` (optional) is the Bill's linked Member doc, used to enrich the
// response with owner/flat/area info the real Bill documents don't carry
// themselves — see Bill Format sheet (bill_format_sheet.dart) which needs it.
function normalizeBill(b: any, member?: any) {
  const amount = b.amount ?? b.totalAmount ?? b.totalBillDue ?? 0
  const amountPaid = b.amountPaid ?? 0
  const status = b.status ?? (amountPaid >= amount ? "Paid" : amountPaid > 0 ? "Partial" : "Unpaid")
  return {
    ...b,
    amount,
    amountPaid,
    status,
    dueDate: b.dueDate ?? null,
    periodLabel: periodLabelFrom(b),
    ownerName: member?.ownerName ?? b.ownerName ?? null,
    flatNo: member?.flatNo ?? b.flatNo ?? null,
    wing: member?.wing ?? b.wing ?? null,
    areaSqft: member?.carpetAreaSqft ?? b.areaSqft ?? null,
    billHtml: b.billHtml && String(b.billHtml).trim().length > 0 ? b.billHtml : buildFallbackBillHtml(b, amount),
  }
}

// Real imported bills (see mongo_export/bills.json) ship a server-rendered
// `billHtml`; bills created via POST /v1/bills below don't. Rather than let
// "Save PDF" have two different code paths depending on bill origin, always
// guarantee *some* printable HTML here.
function buildFallbackBillHtml(b: any, amount: number): string {
  const label = periodLabelFrom(b)
  const charges = b.charges && typeof b.charges === "object" ? b.charges : { [b.title ?? "Maintenance Charges"]: amount }
  const rows = Object.entries(charges)
    .map(([k, v]) => `<tr><td style="padding:6px 0;">${k}</td><td style="padding:6px 0;text-align:right;">₹${v}</td></tr>`)
    .join("")
  return `
<div style="font-family:Arial,sans-serif;font-size:14px;color:#1f2937;padding:24px;max-width:600px;margin:0 auto;">
  <div style="background:linear-gradient(135deg,#1e40af,#3b82f6);color:white;padding:20px;border-radius:10px;margin-bottom:16px;">
    <div style="font-size:11px;letter-spacing:1px;opacity:.8;">MAINTENANCE BILL</div>
    <div style="font-size:18px;font-weight:700;margin-top:4px;">${label}</div>
  </div>
  <table style="width:100%;border-collapse:collapse;">${rows}</table>
  <div style="display:flex;justify-content:space-between;font-weight:700;border-top:2px solid #1e40af;padding-top:8px;margin-top:8px;">
    <span>Total</span><span>₹${amount}</span>
  </div>
</div>`
}
```

Leave `POST /` (bill creation) unchanged.

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run tests/api/bills.api.test.ts`
Expected: PASS (all tests, including the pre-existing `GET /v1/bills` describe block — its assertions check `_id`/`memberId`/`amount` fields which are all still present; the new response fields are additive).

- [ ] **Step 5: Commit**

```bash
git add apps/mobile-backend/src/modules/bills/bill.controller.ts apps/mobile-backend/tests/api/bills.api.test.ts
git commit -m "feat(backend): enrich GET /bills with periodLabel, owner/flat/area, billHtml fallback"
```

---

### Task 5: `POST /v1/bills/:id/pay` writes a Transaction + Receipt

**Files:**
- Modify: `apps/mobile-backend/src/modules/bills/bill.controller.ts` (the `/:id/pay` handler)
- Modify: `apps/mobile-backend/tests/api/bills.api.test.ts`

**Interfaces:**
- Consumes: `Transaction`, `Receipt` (Task 2), `periodLabelFrom` (Task 1).
- Produces: after a successful pay, exactly one new `Transaction` (`type: "Credit"`) and one new `Receipt` document exist for that `(billId, amount)`, both consumable by Tasks 6/7 (`GET /ledger`, `GET /receipts`).

- [ ] **Step 1: Write the failing test**

Add to `apps/mobile-backend/tests/api/bills.api.test.ts` (new imports: `Transaction, Receipt` from `../../src/models/index.js`; append inside the existing `describe("POST /v1/bills/:id/pay", ...)` block):

```typescript
  it("creates a Transaction (Credit) and a Receipt on successful payment", async () => {
    const societyId = randomObjectId()
    const memberId = randomObjectId()
    const bill = await Bill.create(makeBill({ societyId, memberId, billPeriodId: "2026-06", amount: 1000, amountPaid: 0 }))
    const token = bearerToken({ role: ROLES.MEMBER, societyId: String(societyId), memberId: String(memberId) })

    const res = await request(app).post(`/v1/bills/${bill._id}/pay`).set(authHeader(token)).send({
      amount: 1000, paymentMode: "UPI",
    })
    expect(res.status).toBe(200)

    const txns = await Transaction.find({ referenceId: bill._id })
    expect(txns).toHaveLength(1)
    expect(txns[0].type).toBe("Credit")
    expect(txns[0].amount).toBe(1000)
    expect(String(txns[0].memberId)).toBe(String(memberId))

    const receipts = await Receipt.find({ billId: bill._id })
    expect(receipts).toHaveLength(1)
    expect(receipts[0].amount).toBe(1000)
    expect(receipts[0].receiptNo).toEqual(expect.any(String))
    expect(receipts[0].receiptNo.length).toBeGreaterThan(0)
  })
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run tests/api/bills.api.test.ts`
Expected: FAIL — `txns` has length 0.

- [ ] **Step 3: Write minimal implementation**

Replace the `/:id/pay` handler in `apps/mobile-backend/src/modules/bills/bill.controller.ts`:

```typescript
// Member pays (full or partial) their own bill; admin/secretary can record payment for any bill in the society
billRouter.post("/:id/pay", async (req, res) => {
  const parsed = paymentSchema.safeParse({ ...req.body, billId: req.params.id })
  if (!parsed.success) return res.status(400).json({ error: parsed.error.flatten() })
  const isAdmin = BILLING_WRITE_ROLES.includes(req.auth!.role)
  const filter: Record<string, unknown> = { _id: req.params.id, societyId: (req as any).societyId }
  if (!isAdmin) filter.memberId = req.auth!.memberId
  const bill = await Bill.findOne(filter)
  if (!bill) return res.status(404).json({ error: "Not found" })
  const total = (bill as any).amount ?? (bill as any).totalAmount ?? (bill as any).totalBillDue ?? 0
  const paid = ((bill as any).amountPaid ?? 0) + parsed.data.amount
  ;(bill as any).amountPaid = paid
  ;(bill as any).status = paid >= total ? BILL_STATUS.PAID : BILL_STATUS.PARTIAL
  await bill.save()

  const payingMemberId = isAdmin ? (bill as any).memberId : req.auth!.memberId
  const balanceAfter = Math.max(total - paid, 0)
  const billPeriodId = (bill as any).billPeriodId ?? (bill as any).period ?? null
  const receiptNo = `RCP-${Date.now()}-${randomUUID().replace(/-/g, "").slice(0, 4).toUpperCase()}`
  const txnId = `TXN${randomUUID().replace(/-/g, "").slice(0, 14).toUpperCase()}`

  await Promise.all([
    Payment.create({
      societyId: (req as any).societyId, billId: bill._id, memberId: payingMemberId,
      amount: parsed.data.amount, paymentMode: parsed.data.paymentMode,
    }),
    Transaction.create({
      transactionId: txnId,
      date: new Date(),
      memberId: payingMemberId,
      societyId: (req as any).societyId,
      type: "Credit",
      category: "Payment",
      description: `Payment received for ${periodLabelFrom(bill.toObject())}`,
      amount: parsed.data.amount,
      balanceAfterTransaction: balanceAfter,
      referenceId: bill._id,
      referenceModel: "Bill",
      billPeriodId,
      paymentMode: parsed.data.paymentMode,
    }),
    Receipt.create({
      receiptNo,
      billId: bill._id,
      billPeriodId,
      memberId: payingMemberId,
      societyId: (req as any).societyId,
      amount: parsed.data.amount,
      paymentMode: parsed.data.paymentMode,
      paidAt: new Date(),
      transactionId: txnId,
      status: "Generated",
    }),
  ])

  return res.json({ ...(bill as any).toObject(), amount: total, periodLabel: periodLabelFrom(bill.toObject()) }) // change stream -> PAYMENT_RECEIVED notification
})
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run tests/api/bills.api.test.ts`
Expected: PASS (all tests, including the pre-existing "a different member cannot pay someone else's bill (404)" — verify it still returns 404 before any Transaction/Receipt code runs).

- [ ] **Step 5: Commit**

```bash
git add apps/mobile-backend/src/modules/bills/bill.controller.ts apps/mobile-backend/tests/api/bills.api.test.ts
git commit -m "feat(backend): write a Transaction and Receipt on every bill payment"
```

---

### Task 6: `GET /v1/ledger` endpoint

**Files:**
- Create: `apps/mobile-backend/src/modules/ledger/ledger.controller.ts`
- Modify: `apps/mobile-backend/src/app.ts`
- Create: `apps/mobile-backend/tests/api/ledger.api.test.ts`

**Interfaces:**
- Consumes: `Transaction` (Task 2).
- Produces: `GET /v1/ledger` → `Array<{ _id, date, description, type: "Debit"|"Credit", amount, balanceAfterTransaction, paymentMode, billPeriodId }>`, sorted newest first. Consumed by Flutter Task 14.

- [ ] **Step 1: Write the failing test**

```typescript
import { describe, it, expect } from "vitest"
import request from "supertest"
import { ROLES } from "@aapli/constants"
import { createApp } from "../helpers/app.js"
import { bearerToken, authHeader } from "../helpers/auth.js"
import { makeTransaction } from "../factories/index.js"
import { randomObjectId } from "../utils/randomObjectId.js"
import { Transaction } from "../../src/models/index.js"

const app = createApp()

describe("GET /v1/ledger", () => {
  it("returns a member's own transactions, newest first, in the normalized shape", async () => {
    const societyId = randomObjectId()
    const memberId = randomObjectId()
    await Transaction.create(makeTransaction({ societyId, memberId, date: new Date("2026-05-01"), type: "Debit", amount: 594.25, description: "Bill generated for 2026-05" }))
    await Transaction.create(makeTransaction({ societyId, memberId, date: new Date("2026-05-13"), type: "Credit", amount: 594.25, description: "Payment received" }))

    const token = bearerToken({ role: ROLES.MEMBER, societyId: String(societyId), memberId: String(memberId) })
    const res = await request(app).get("/v1/ledger").set(authHeader(token))

    expect(res.status).toBe(200)
    expect(res.body).toHaveLength(2)
    expect(res.body[0].description).toBe("Payment received") // newest first
    expect(res.body[0].type).toBe("Credit")
    expect(res.body[1].type).toBe("Debit")
  })

  it("does not return another member's transactions", async () => {
    const societyId = randomObjectId()
    const mine = randomObjectId()
    const theirs = randomObjectId()
    await Transaction.create(makeTransaction({ societyId, memberId: mine }))
    await Transaction.create(makeTransaction({ societyId, memberId: theirs }))

    const token = bearerToken({ role: ROLES.MEMBER, societyId: String(societyId), memberId: String(mine) })
    const res = await request(app).get("/v1/ledger").set(authHeader(token))
    expect(res.status).toBe(200)
    expect(res.body).toHaveLength(1)
  })

  it("returns 401 with no token", async () => {
    const res = await request(app).get("/v1/ledger")
    expect(res.status).toBe(401)
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run tests/api/ledger.api.test.ts`
Expected: FAIL — 404 (route not mounted).

- [ ] **Step 3: Write minimal implementation**

Create `apps/mobile-backend/src/modules/ledger/ledger.controller.ts`:

```typescript
import { Router } from "express"
import { BILLING_WRITE_ROLES } from "@aapli/constants"
import { Transaction } from "../../models/index.js"
import { requireAuth } from "../../middleware/auth.js"
import { withTenant } from "../../middleware/tenancy.js"

export const ledgerRouter = Router()
ledgerRouter.use(requireAuth, withTenant)

// Members see their own transaction history; admins/secretaries see the
// whole society's. Reads the real `transactions` collection (Task 2 model)
// instead of the member app deriving debit/credit rows from /bills client-side.
ledgerRouter.get("/", async (req, res) => {
  const isAdmin = BILLING_WRITE_ROLES.includes(req.auth!.role)
  const filter: Record<string, unknown> = { societyId: (req as any).societyId }
  if (!isAdmin) filter.memberId = req.auth!.memberId
  const entries = await Transaction.find(filter).sort({ date: -1, createdAt: -1 }).limit(200).lean()
  return res.json(entries.map((e: any) => ({
    _id: String(e._id),
    date: e.date ?? e.createdAt ?? null,
    description: e.description ?? `${e.category ?? "Transaction"}${e.billPeriodId ? ` — ${e.billPeriodId}` : ""}`,
    type: e.type === "Credit" ? "Credit" : "Debit",
    amount: Math.abs(e.amount ?? 0),
    balanceAfterTransaction: e.balanceAfterTransaction ?? null,
    paymentMode: e.paymentMode ?? null,
    billPeriodId: e.billPeriodId ?? null,
  })))
})
```

In `apps/mobile-backend/src/app.ts`, add the import and mount:

```typescript
import { ledgerRouter } from "./modules/ledger/ledger.controller.js"
```

```typescript
  app.use("/v1/ledger", ledgerRouter)
```

(add both lines alongside the existing `billRouter` import/mount)

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run tests/api/ledger.api.test.ts`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add apps/mobile-backend/src/modules/ledger apps/mobile-backend/src/app.ts apps/mobile-backend/tests/api/ledger.api.test.ts
git commit -m "feat(backend): add GET /v1/ledger backed by the real transactions collection"
```

---

### Task 7: `GET /v1/receipts` endpoint

**Files:**
- Create: `apps/mobile-backend/src/modules/receipts/receipt.controller.ts`
- Modify: `apps/mobile-backend/src/app.ts`
- Create: `apps/mobile-backend/tests/api/receipts.api.test.ts`

**Interfaces:**
- Consumes: `Receipt` (Task 2), `periodLabelFrom` (Task 1).
- Produces: `GET /v1/receipts` → `Array<{ _id, receiptNo, periodLabel, billPeriodId, amount, paymentMode, paidAt, transactionId, status }>`, sorted newest first. Consumed by Flutter Task 15.

- [ ] **Step 1: Write the failing test**

```typescript
import { describe, it, expect } from "vitest"
import request from "supertest"
import { ROLES } from "@aapli/constants"
import { createApp } from "../helpers/app.js"
import { bearerToken, authHeader } from "../helpers/auth.js"
import { makeReceipt } from "../factories/index.js"
import { randomObjectId } from "../utils/randomObjectId.js"
import { Receipt } from "../../src/models/index.js"

const app = createApp()

describe("GET /v1/receipts", () => {
  it("returns a member's own receipts with a formatted periodLabel", async () => {
    const societyId = randomObjectId()
    const memberId = randomObjectId()
    await Receipt.create(makeReceipt({ societyId, memberId, billPeriodId: "2026-05", receiptNo: "RCP-1778759578625-E6RL", amount: 594.25 }))

    const token = bearerToken({ role: ROLES.MEMBER, societyId: String(societyId), memberId: String(memberId) })
    const res = await request(app).get("/v1/receipts").set(authHeader(token))

    expect(res.status).toBe(200)
    expect(res.body).toHaveLength(1)
    expect(res.body[0].receiptNo).toBe("RCP-1778759578625-E6RL")
    expect(res.body[0].periodLabel).toBe("May 2026")
    expect(res.body[0].amount).toBe(594.25)
  })

  it("does not return another member's receipts", async () => {
    const societyId = randomObjectId()
    const mine = randomObjectId()
    const theirs = randomObjectId()
    await Receipt.create(makeReceipt({ societyId, memberId: mine }))
    await Receipt.create(makeReceipt({ societyId, memberId: theirs }))

    const token = bearerToken({ role: ROLES.MEMBER, societyId: String(societyId), memberId: String(mine) })
    const res = await request(app).get("/v1/receipts").set(authHeader(token))
    expect(res.status).toBe(200)
    expect(res.body).toHaveLength(1)
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `npx vitest run tests/api/receipts.api.test.ts`
Expected: FAIL — 404 (route not mounted).

- [ ] **Step 3: Write minimal implementation**

Create `apps/mobile-backend/src/modules/receipts/receipt.controller.ts`:

```typescript
import { Router } from "express"
import { BILLING_WRITE_ROLES } from "@aapli/constants"
import { Receipt } from "../../models/index.js"
import { requireAuth } from "../../middleware/auth.js"
import { withTenant } from "../../middleware/tenancy.js"
import { periodLabelFrom } from "../../lib/periodLabel.js"

export const receiptRouter = Router()
receiptRouter.use(requireAuth, withTenant)

// Members see their own receipts; admins/secretaries see the whole
// society's. Reads the real `receipts` collection (Task 2 model) instead of
// the member app deriving one fake receipt per paid bill client-side.
receiptRouter.get("/", async (req, res) => {
  const isAdmin = BILLING_WRITE_ROLES.includes(req.auth!.role)
  const filter: Record<string, unknown> = { societyId: (req as any).societyId }
  if (!isAdmin) filter.memberId = req.auth!.memberId
  const receipts = await Receipt.find(filter).sort({ paidAt: -1, createdAt: -1 }).limit(200).lean()
  return res.json(receipts.map((r: any) => ({
    _id: String(r._id),
    receiptNo: r.receiptNo ?? `RCPT-${String(r._id).slice(-6).toUpperCase()}`,
    periodLabel: periodLabelFrom(r),
    billPeriodId: r.billPeriodId ?? null,
    amount: r.amount ?? 0,
    paymentMode: r.paymentMode ?? null,
    paidAt: r.paidAt ?? r.createdAt ?? null,
    transactionId: r.transactionId ?? null,
    status: r.status ?? "Generated",
  })))
})
```

In `apps/mobile-backend/src/app.ts`, add the import and mount:

```typescript
import { receiptRouter } from "./modules/receipts/receipt.controller.js"
```

```typescript
  app.use("/v1/receipts", receiptRouter)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npx vitest run tests/api/receipts.api.test.ts`
Expected: PASS (2 tests)

- [ ] **Step 5: Run the full backend suite to confirm nothing else broke**

Run (from `apps/mobile-backend`): `npm run test:coverage`
Expected: all tests PASS, coverage thresholds (`lines: 58, statements: 58, functions: 48, branches: 65`) still met — the new modules add tested lines, which should only help the ratio.

- [ ] **Step 6: Commit**

```bash
git add apps/mobile-backend/src/modules/receipts apps/mobile-backend/src/app.ts apps/mobile-backend/tests/api/receipts.api.test.ts
git commit -m "feat(backend): add GET /v1/receipts backed by the real receipts collection"
```

---

### Task 8: Flutter — `printing`/`pdf` deps + `billTitle()` helper, fix every "null" call site

**Files:**
- Modify: `apps/mobile-app/pubspec.yaml`
- Modify: `apps/mobile-app/lib/features/member/bills_page.dart:9,209`
- Modify: `apps/mobile-app/lib/features/member/pulse/bill_detail_sheet.dart:16,128,137`
- Modify: `apps/mobile-app/lib/features/member/pulse/bill_format_sheet.dart:64,156`
- Modify: `apps/mobile-app/test/fixtures/bill_fixtures.dart`
- Create: `apps/mobile-app/test/unit/bill_title_test.dart`

**Interfaces:**
- Produces: `String billTitle(Map bill)` exported from `bills_page.dart` (alongside existing `inr`/`effectiveStatus`), consumed by Tasks 10/11/12/13.

- [ ] **Step 1: Write the failing test**

Create `apps/mobile-app/test/unit/bill_title_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:aapli_society/features/member/bills_page.dart';

void main() {
  group('billTitle', () {
    test('prefers periodLabel (the field the backend now always sends)', () {
      expect(billTitle({'periodLabel': 'May 2026', 'title': null, 'period': null}), 'May 2026');
    });

    test('falls back to title, then period, then "Bill" — never renders the string "null"', () {
      expect(billTitle({'title': 'Custom Title'}), 'Custom Title');
      expect(billTitle({'period': '2026-Q2'}), '2026-Q2');
      expect(billTitle(<String, dynamic>{}), 'Bill');
      expect(billTitle({'title': null, 'period': null}), 'Bill');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run (from `apps/mobile-app`): `flutter test test/unit/bill_title_test.dart`
Expected: FAIL — `billTitle` is not defined.

- [ ] **Step 3: Write minimal implementation**

In `apps/mobile-app/pubspec.yaml`, add under `dependencies:` (alongside `share_plus: ^9.0.0`):

```yaml
  printing: ^5.13.4
  pdf: ^3.11.1
```

Run: `flutter pub get` (from `apps/mobile-app`)

In `apps/mobile-app/lib/features/member/bills_page.dart`, add after the existing `inr()` function (line 9):

```dart
// The backend now always sends `periodLabel` (see
// apps/mobile-backend/src/lib/periodLabel.ts) — this is the single place
// every bill-title display in the app should read from, instead of each
// call site doing its own `bill['title'] ?? bill['period']` chain, which
// rendered the literal string "null" whenever both were absent.
String billTitle(Map bill) => '${bill['periodLabel'] ?? bill['title'] ?? bill['period'] ?? 'Bill'}';
```

Replace line 209 in the same file:

```dart
                  Text(billTitle(bill), style: const TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.w700)),
```

In `apps/mobile-app/lib/features/member/pulse/bill_detail_sheet.dart`, add `import '../bills_page.dart' show inr, effectiveStatus, billTitle;` (replacing the existing `show inr, effectiveStatus` import), then:
- Line 16: `title: billTitle(bill),`
- Line 128: `onTap: () => showPulseToast(context, 'Saved ${billTitle(bill)} bill to Downloads', kind: PulseToastKind.success),` (this call site is fully replaced by real PDF export in Task 13 — this step just stops it from printing "null" in the interim)
- Line 137: `onTap: () => Share.share('${billTitle(bill)} bill — ${inr(amount)}, balance ${inr(settled ? 0 : balance)}'),`

In `apps/mobile-app/lib/features/member/pulse/bill_format_sheet.dart`, add `billTitle` to the existing `show inr` import (`import '../bills_page.dart' show inr, billTitle;`), then:
- Line 64: `_Meta(label: 'Period', value: billTitle(bill)),`
- Line 156: `onTap: () => Share.share('${billTitle(bill)} bill — Total ${inr(amount)}'),`

In `apps/mobile-app/test/fixtures/bill_fixtures.dart`, add `'periodLabel'` to both sample maps so fixtures match the real backend shape:

```dart
const Map<String, dynamic> sampleBillPaid = {
  '_id': 'bill_1',
  'periodLabel': 'June 2026',
  'title': 'Maintenance - June 2026',
  'period': '2026-06',
  'status': 'Paid',
  'amount': 3500,
  'amountPaid': 3500,
  'dueDate': '2026-06-10T00:00:00.000Z',
};

const Map<String, dynamic> sampleBillDue = {
  '_id': 'bill_2',
  'periodLabel': 'July 2026',
  'title': 'Maintenance - July 2026',
  'period': '2026-07',
  'status': 'Due',
  'amount': 3500,
  'amountPaid': 0,
  'dueDate': '2026-07-10T00:00:00.000Z',
};
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/bill_title_test.dart`
Expected: PASS (2 tests)

- [ ] **Step 5: Run static analysis to catch the call-site edits**

Run: `flutter analyze lib/features/member`
Expected: no new errors (only pre-existing warnings, if any, unrelated to these files)

- [ ] **Step 6: Commit**

```bash
git add apps/mobile-app/pubspec.yaml apps/mobile-app/pubspec.lock apps/mobile-app/lib/features/member/bills_page.dart apps/mobile-app/lib/features/member/pulse/bill_detail_sheet.dart apps/mobile-app/lib/features/member/pulse/bill_format_sheet.dart apps/mobile-app/test/fixtures/bill_fixtures.dart apps/mobile-app/test/unit/bill_title_test.dart
git commit -m "fix(app): add billTitle() helper, kill every literal-\"null\" bill title"
```

---

### Task 9: Flutter — real display name / society name helpers

**Files:**
- Create: `apps/mobile-app/lib/features/member/pulse/member_display.dart`
- Create: `apps/mobile-app/test/unit/member_display_test.dart`
- Modify: `apps/mobile-app/test/fixtures/auth_fixtures.dart`

**Interfaces:**
- Produces: `String resolveDisplayName(Map<String, dynamic> user)`, `String? resolveSocietyName(Map<String, dynamic> user, Map? activeProfile)` — consumed by Tasks 10 (dashboard) and 11 (profile).

- [ ] **Step 1: Write the failing test**

Create `apps/mobile-app/test/unit/member_display_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:aapli_society/features/member/pulse/member_display.dart';

void main() {
  group('resolveDisplayName', () {
    test('prefers the linked Member\'s ownerName over the login username', () {
      final user = {'username': 'gs_salmank_101_22', 'member': {'ownerName': 'Tanvi Bansal'}};
      expect(resolveDisplayName(user), 'Tanvi Bansal');
    });

    test('falls back to username when member is null or ownerName is blank', () {
      expect(resolveDisplayName({'username': 'gs_salmank_101_22', 'member': null}), 'gs_salmank_101_22');
      expect(resolveDisplayName({'username': 'gs_salmank_101_22', 'member': {'ownerName': ''}}), 'gs_salmank_101_22');
    });

    test('falls back to "there" when nothing is available', () {
      expect(resolveDisplayName(<String, dynamic>{}), 'there');
    });
  });

  group('resolveSocietyName', () {
    test('prefers the linked Society\'s name over the cached profile.societyName', () {
      final user = {'society': {'name': 'Sunrise Complex'}};
      final profile = {'societyName': 'stale-cached-name'};
      expect(resolveSocietyName(user, profile), 'Sunrise Complex');
    });

    test('falls back to profile.societyName when society is null', () {
      final user = {'society': null};
      final profile = {'societyName': 'Palm Residency'};
      expect(resolveSocietyName(user, profile), 'Palm Residency');
    });

    test('returns null when neither source has a name', () {
      expect(resolveSocietyName(<String, dynamic>{}, null), null);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run (from `apps/mobile-app`): `flutter test test/unit/member_display_test.dart`
Expected: FAIL — cannot find `package:aapli_society/features/member/pulse/member_display.dart`.

- [ ] **Step 3: Write minimal implementation**

Create `apps/mobile-app/lib/features/member/pulse/member_display.dart`:

```dart
/// Pure helpers for resolving what to show as a person's/society's display
/// name from the `GET /auth/me` response shape — `user['member']` and
/// `user['society']` are attached server-side by
/// `apps/mobile-backend/src/modules/auth/auth.controller.ts` (Task 3 of
/// `docs/superpowers/plans/2026-07-12-member-data-ui-fill.md`).
/// `username` is a login handle (e.g. "gs_salmank_101_22"), never a real
/// person's name — always prefer the linked Member's `ownerName` when it's
/// present and non-blank.
library;

String resolveDisplayName(Map<String, dynamic> user) {
  final member = user['member'] as Map?;
  final ownerName = member?['ownerName']?.toString().trim();
  if (ownerName != null && ownerName.isNotEmpty) return ownerName;
  final username = user['username']?.toString();
  return (username != null && username.isNotEmpty) ? username : 'there';
}

String? resolveSocietyName(Map<String, dynamic> user, Map? activeProfile) {
  final society = user['society'] as Map?;
  final name = society?['name']?.toString().trim();
  if (name != null && name.isNotEmpty) return name;
  final profileName = activeProfile?['societyName']?.toString().trim();
  return (profileName != null && profileName.isNotEmpty) ? profileName : null;
}
```

In `apps/mobile-app/test/fixtures/auth_fixtures.dart`, add `member`/`society` to the sample so widget-level fixtures reflect the real shape:

```dart
const Map<String, dynamic> sampleAuthMeResponse = {
  'user': {
    '_id': 'user_1',
    'username': 'gs_salmank_101_22',
    'name': 'Asha Kulkarni',
    'email': 'asha.kulkarni@example.com',
    'flatNumber': 'B-402',
    'member': {
      'ownerName': 'Asha Kulkarni',
      'flatNo': '402',
      'wing': 'B',
      'flatType': '2BHK',
      'ownershipType': 'Owned',
      'carpetAreaSqft': 950,
      'builtUpAreaSqft': 1050,
      'hasVotingRights': true,
      'contactNumber': '9876500000',
      'whatsappNumber': '9876500000',
      'parkingSlots': [
        {'slotNumber': 'P-B-04', 'type': 'Covered', 'vehicleType': 'Four-Wheeler'},
      ],
      'familyMembers': [
        {'name': 'Rohan Kulkarni', 'relation': 'Spouse', 'age': 33},
      ],
    },
    'society': {'_id': 'society_1', 'name': 'Sunrise Complex', 'address': '456 Park Avenue, Pune'},
  },
  'claims': {
    'role': 'member',
    'societyId': 'society_1',
  },
};
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/unit/member_display_test.dart`
Expected: PASS (6 tests)

- [ ] **Step 5: Commit**

```bash
git add apps/mobile-app/lib/features/member/pulse/member_display.dart apps/mobile-app/test/unit/member_display_test.dart apps/mobile-app/test/fixtures/auth_fixtures.dart
git commit -m "feat(app): add resolveDisplayName/resolveSocietyName helpers"
```

---

### Task 10: Flutter — dashboard greeting + society label use real data

**Files:**
- Modify: `apps/mobile-app/lib/features/member/dashboard_page.dart:75-84,128,134`

**Interfaces:**
- Consumes: `resolveDisplayName`, `resolveSocietyName` (Task 9).

- [ ] **Step 1: Manual verification target (no new automated test — pure display wiring already covered by Task 9's unit tests; this step only rewires the widget to call them)**

The existing test suite has no widget test for `DashboardPage` today (only `test/widget/accessibility_test.dart` and `async_view_test.dart` exist under `test/widget/`) — this task keeps that scope; verification happens via Task 16's manual pass.

- [ ] **Step 2: Wire the helpers into `dashboard_page.dart`**

Add the import:

```dart
import 'pulse/member_display.dart';
```

Replace lines 75-84:

```dart
    final displayName = resolveDisplayName(user);
    final firstName = displayName.split(RegExp(r'\s+')).first;
    final profiles = (user['profiles'] as List?) ?? const [];
    final activeProfile = profiles.cast<Map?>().firstWhere(
          (p) => p != null && '${p['_id']}' == '${claims['activeProfileId']}',
          orElse: () => profiles.isNotEmpty ? profiles.first as Map : null,
        );
    final societyName = resolveSocietyName(user, activeProfile);
    final flatSub = activeProfile == null
        ? null
        : 'Flat ${activeProfile['wing'] ?? ''}${activeProfile['wing'] != null && activeProfile['wing'] != '' ? '-' : ''}${activeProfile['flatNo'] ?? ''}${societyName != null ? ' · $societyName' : ''}';
```

Replace line 128 (`PulseAvatar(name: username, size: 44, ring: true),`):

```dart
                    PulseAvatar(name: displayName, size: 44, ring: true),
```

Line 134 already reads `firstName`, which is now derived from `displayName` — no further edit needed there.

- [ ] **Step 3: Run static analysis**

Run: `flutter analyze lib/features/member/dashboard_page.dart`
Expected: no errors (confirms `username`/`firstName` were fully replaced — an unused-variable warning here would mean a stale reference was missed)

- [ ] **Step 4: Commit**

```bash
git add apps/mobile-app/lib/features/member/dashboard_page.dart
git commit -m "fix(app): dashboard greeting and society label use real Member/Society data"
```

---

### Task 11: Flutter — Profile page real fields + parking/family list UI

**Files:**
- Modify: `apps/mobile-app/lib/features/member/member_profile_page.dart`

**Interfaces:**
- Consumes: `resolveDisplayName`, `resolveSocietyName` (Task 9).

- [ ] **Step 1: Wire the helpers and real Member fields**

Add the import: `import 'pulse/member_display.dart';`

Replace lines 28-39:

```dart
    final displayName = resolveDisplayName(user);
    final email = user['email']?.toString();
    final profiles = (user['profiles'] as List?) ?? const [];
    final activeProfile = profiles.cast<Map?>().firstWhere(
          (p) => p != null && '${p['_id']}' == '${claims['activeProfileId']}',
          orElse: () => profiles.isNotEmpty ? profiles.first as Map : null,
        );
    final member = user['member'] as Map?;
    final flatNo = (member?['flatNo'] ?? activeProfile?['flatNo'])?.toString();
    final wing = (member?['wing'] ?? activeProfile?['wing'])?.toString();
    final societyName = resolveSocietyName(user, activeProfile);
    final role = claims['role']?.toString() ?? activeProfile?['role']?.toString();
    final status = activeProfile?['status']?.toString();
    final carpetArea = member?['carpetAreaSqft'];
    final builtUpArea = member?['builtUpAreaSqft'];
    final areaText = carpetArea != null
        ? '$carpetArea sqft (carpet)${builtUpArea != null ? ' · $builtUpArea sqft (built-up)' : ''}'
        : null;
    final votingRights = member?['hasVotingRights'];
    final votingText = votingRights == null ? null : (votingRights == true ? 'Eligible' : 'Not eligible');
    final parkingSlots = (member?['parkingSlots'] as List?)?.cast<Map>() ?? const <Map>[];
    final familyMembers = (member?['familyMembers'] as List?)?.cast<Map>() ?? const <Map>[];
```

Replace `_Header(username: username, ...)` (was line 45) with:

```dart
          _Header(username: displayName, wing: wing, flatNo: flatNo, societyName: societyName, role: role, status: status),
```

Replace the `_Section(icon: Icons.home_work_outlined, title: 'Flat details', rows: [...])` block:

```dart
          _Section(
            icon: Icons.home_work_outlined,
            title: 'Flat details',
            rows: [
              ('Flat', flatNo != null ? '$flatNo${wing != null && wing.isNotEmpty ? ' ($wing wing)' : ''}' : null),
              ('Type', member?['flatType']?.toString()),
              ('Ownership', member?['ownershipType']?.toString()),
              ('Carpet area', areaText),
              ('Voting rights', votingText),
            ],
          ),
```

Replace the `_Section(icon: Icons.call_outlined, title: 'Contact', rows: [...])` block:

```dart
          _Section(
            icon: Icons.call_outlined,
            title: 'Contact',
            rows: [
              ('Email', email),
              ('Phone', (member?['contactNumber'] ?? user['phone'])?.toString()),
              ('WhatsApp', member?['whatsappNumber']?.toString()),
            ],
          ),
```

Replace these two lines:

```dart
          _Section(icon: Icons.local_parking_outlined, title: 'Parking', rows: const [('Slots', null)]),
          _Section(icon: Icons.family_restroom_outlined, title: 'Family members', rows: const [('Members', null)]),
```

with:

```dart
          _ParkingSection(slots: parkingSlots),
          _FamilySection(members: familyMembers),
```

(leave the `_Section(icon: Icons.emergency_outlined, title: 'Emergency contact', ...)` line exactly as-is — no real field backs it, per `apps/mobile-app/MEMBER_V2_GAPS.md`, so it correctly keeps showing "Not available yet")

- [ ] **Step 2: Add the two new list-rendering widgets**

Append to the bottom of `apps/mobile-app/lib/features/member/member_profile_page.dart` (after the existing `_Tile` class):

```dart
class _ParkingSection extends StatelessWidget {
  final List<Map> slots;
  const _ParkingSection({required this.slots});

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: PulseCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.local_parking_outlined, size: 16, color: t.brand),
                const SizedBox(width: 8),
                Text('Parking', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: t.fg2)),
              ],
            ),
            const SizedBox(height: 10),
            if (slots.isEmpty)
              Text('Not available yet', style: TextStyle(fontSize: 12.5, color: t.fg5, fontStyle: FontStyle.italic))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: slots.map((s) {
                  final label = '${s['slotNumber'] ?? '—'}';
                  final sub = [s['type'], s['vehicleType']]
                      .where((v) => v != null && '$v'.isNotEmpty)
                      .join(' · ');
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(color: t.brandSoft, borderRadius: BorderRadius.circular(PulseTokens.radiusSm)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: t.brand)),
                        if (sub.isNotEmpty) Text(sub, style: TextStyle(fontSize: 10.5, color: t.fg4)),
                      ],
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }
}

class _FamilySection extends StatelessWidget {
  final List<Map> members;
  const _FamilySection({required this.members});

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: PulseCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.family_restroom_outlined, size: 16, color: t.brand),
                const SizedBox(width: 8),
                Text('Family members', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: t.fg2)),
              ],
            ),
            const SizedBox(height: 10),
            if (members.isEmpty)
              Text('Not available yet', style: TextStyle(fontSize: 12.5, color: t.fg5, fontStyle: FontStyle.italic))
            else
              ...members.map((m) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('${m['name'] ?? '—'}', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: t.fg1)),
                        ),
                        Text(
                          [m['relation'], m['age'] != null ? '${m['age']} yrs' : null]
                              .where((v) => v != null && '$v'.isNotEmpty)
                              .join(' · '),
                          style: TextStyle(fontSize: 11.5, color: t.fg4),
                        ),
                      ],
                    ),
                  )),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Run static analysis**

Run: `flutter analyze lib/features/member/member_profile_page.dart`
Expected: no errors

- [ ] **Step 4: Commit**

```bash
git add apps/mobile-app/lib/features/member/member_profile_page.dart
git commit -m "feat(app): Profile page shows real flat/contact/parking/family data"
```

---

### Task 12: Flutter — PDF export helpers

**Files:**
- Create: `apps/mobile-app/lib/features/member/pulse/bill_pdf.dart`

**Interfaces:**
- Consumes: `printing`, `pdf` packages (Task 8).
- Produces: `Future<Uint8List> renderBillPdf(Map bill)`, `Future<Uint8List> renderReceiptPdf(Map receipt, {required String periodLabel, required String Function(num) formatInr})` — consumed by Tasks 13/14/15.

- [ ] **Step 1: Write the implementation directly (pure PDF-byte builders — verified visually in Task 16's manual pass rather than golden-tested, matching this codebase's existing convention of not golden-testing PDF/print output)**

Create `apps/mobile-app/lib/features/member/pulse/bill_pdf.dart`:

```dart
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Converts a bill's server-rendered `billHtml` (see
/// `apps/mobile-backend/src/modules/bills/bill.controller.ts`
/// `buildFallbackBillHtml` — every bill from `GET /bills` is guaranteed to
/// have non-empty `billHtml`) into real PDF bytes for Save/Share, replacing
/// the toast-only placeholders `bill_detail_sheet.dart`/
/// `bill_format_sheet.dart` used before.
Future<Uint8List> renderBillPdf(Map bill) async {
  final html = '${bill['billHtml'] ?? ''}';
  final fallback = '<div style="font-family:Arial;padding:24px;">No bill content available.</div>';
  return Printing.convertHtml(format: PdfPageFormat.a4, html: html.isNotEmpty ? html : fallback);
}

/// Builds a minimal printable receipt PDF client-side. Real `Receipt`
/// documents (see `GET /v1/receipts`) don't carry rendered HTML like bills
/// do, so this constructs a small `pw.Document` directly instead of going
/// through `Printing.convertHtml`.
Future<Uint8List> renderReceiptPdf(
  Map receipt, {
  required String periodLabel,
  required String Function(num) formatInr,
}) async {
  final doc = pw.Document();
  final amount = (receipt['amount'] as num?) ?? 0;
  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a5,
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('PAYMENT RECEIPT', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 12),
          pw.Text('Receipt No: ${receipt['receiptNo'] ?? '—'}'),
          pw.Text('Period: $periodLabel'),
          pw.Text('Payment mode: ${receipt['paymentMode'] ?? '—'}'),
          if (receipt['transactionId'] != null) pw.Text('Transaction ID: ${receipt['transactionId']}'),
          pw.Divider(height: 24),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Amount paid', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
              pw.Text(formatInr(amount), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
            ],
          ),
        ],
      ),
    ),
  );
  return doc.save();
}
```

- [ ] **Step 2: Run static analysis**

Run (from `apps/mobile-app`): `flutter analyze lib/features/member/pulse/bill_pdf.dart`
Expected: no errors

- [ ] **Step 3: Commit**

```bash
git add apps/mobile-app/lib/features/member/pulse/bill_pdf.dart
git commit -m "feat(app): add renderBillPdf/renderReceiptPdf helpers"
```

---

### Task 13: Flutter — Bill Detail + Bill Format sheets use real owner/flat/area/society + real PDF

**Files:**
- Modify: `apps/mobile-app/lib/features/member/pulse/bill_detail_sheet.dart`
- Modify: `apps/mobile-app/lib/features/member/pulse/bill_format_sheet.dart`

**Interfaces:**
- Consumes: `renderBillPdf` (Task 12), `AuthBloc`/`AuthAuthed` (existing, `lib/features/auth/bloc/auth_bloc.dart`).

- [ ] **Step 1: Wire real PDF export into `bill_detail_sheet.dart`**

Add imports:

```dart
import 'package:flutter/services.dart' show Uint8List;
import 'bill_pdf.dart';
```

Replace the "Save PDF" button's `onTap` (was the toast-only line):

```dart
              child: PulseButton(
                label: 'Save PDF',
                icon: Icons.download_outlined,
                variant: PulseBtnVariant.ghost,
                onTap: () async {
                  final bytes = await renderBillPdf(bill);
                  await Printing.layoutPdf(onLayout: (_) async => bytes, name: '${billTitle(bill)}.pdf');
                },
              ),
```

Replace the "Share" button's `onTap`:

```dart
              child: PulseButton(
                label: 'Share',
                icon: Icons.ios_share_rounded,
                variant: PulseBtnVariant.ghost,
                onTap: () async {
                  final bytes = await renderBillPdf(bill);
                  await Printing.sharePdf(bytes: bytes, filename: '${billTitle(bill)}.pdf');
                },
              ),
```

Add `import 'package:printing/printing.dart';` alongside the other imports at the top of the file (remove the now-unused `package:share_plus/share_plus.dart` import only if nothing else in the file still calls `Share.share` — check: it does not, after this edit, so remove it).

- [ ] **Step 2: Wire real owner/flat/area/society + PDF into `bill_format_sheet.dart`**

Add imports:

```dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:printing/printing.dart';
import '../../auth/bloc/auth_bloc.dart';
import 'bill_pdf.dart';
import 'member_display.dart';
```

Change `_BillFormatBody` from `StatelessWidget` to read auth state in `build` (still stateless — just reads `context.watch`):

```dart
  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final auth = context.watch<AuthBloc>().state;
    final user = auth is AuthAuthed ? auth.user : const <String, dynamic>{};
    final societyName = resolveSocietyName(user, null);
    final amount = (bill['amount'] as num?) ?? 0;
```

(the rest of the existing `build` body after `final amount = ...` stays as-is except the edits below)

Replace the header's hardcoded label:

```dart
              Text((societyName ?? 'YOUR SOCIETY').toUpperCase(), style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1)),
```

Replace the `GridView.count` meta children:

```dart
          children: [
            _Meta(label: 'Period', value: billTitle(bill)),
            _Meta(label: 'Flat', value: _flatLabel(bill)),
            _Meta(label: 'Owner', value: '${bill['ownerName'] ?? '—'}'),
            _Meta(label: 'Area', value: bill['areaSqft'] != null ? '${bill['areaSqft']} sqft' : '—'),
          ],
```

Add a small helper method inside `_BillFormatBody` (below `_month`):

```dart
  String _flatLabel(Map bill) {
    final wing = bill['wing']?.toString();
    final flatNo = bill['flatNo']?.toString();
    if (flatNo == null || flatNo.isEmpty) return '—';
    return wing != null && wing.isNotEmpty ? '$wing-$flatNo' : flatNo;
  }
```

Replace the "Save PDF" button's `onTap`:

```dart
              child: PulseButton(
                label: 'Save PDF',
                icon: Icons.download_outlined,
                variant: PulseBtnVariant.secondary,
                onTap: () async {
                  final bytes = await renderBillPdf(bill);
                  await Printing.layoutPdf(onLayout: (_) async => bytes, name: '${billTitle(bill)}.pdf');
                },
              ),
```

Replace the "Share" button's `onTap`:

```dart
              child: PulseButton(
                label: 'Share',
                icon: Icons.ios_share_rounded,
                onTap: () async {
                  final bytes = await renderBillPdf(bill);
                  await Printing.sharePdf(bytes: bytes, filename: '${billTitle(bill)}.pdf');
                },
              ),
```

Remove the `package:share_plus/share_plus.dart` import from this file too (no longer used after this edit).

- [ ] **Step 3: Run static analysis**

Run: `flutter analyze lib/features/member/pulse/bill_detail_sheet.dart lib/features/member/pulse/bill_format_sheet.dart`
Expected: no errors, no unused-import warnings

- [ ] **Step 4: Commit**

```bash
git add apps/mobile-app/lib/features/member/pulse/bill_detail_sheet.dart apps/mobile-app/lib/features/member/pulse/bill_format_sheet.dart
git commit -m "feat(app): bill detail/format sheets show real owner/flat/area/society and export real PDFs"
```

---

### Task 14: Flutter — Ledger page rewritten to `GET /ledger`

**Files:**
- Modify: `apps/mobile-app/lib/features/member/ledger_page.dart`

**Interfaces:**
- Consumes: `GET /v1/ledger` response shape from Task 6.

- [ ] **Step 1: Replace the fetch + rendering logic**

Replace the entire body of `LedgerPage.build`'s `AsyncView<List>` in `apps/mobile-app/lib/features/member/ledger_page.dart`:

```dart
class LedgerPage extends StatelessWidget {
  const LedgerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final dio = context.read<Dio>();
    return Scaffold(
      backgroundColor: t.canvas,
      body: SafeArea(
        child: AsyncView<List>(
          fetch: () async => (await dio.get('/ledger')).data as List,
          builder: (context, entries) {
            final balance = entries.isNotEmpty ? ((entries.first as Map)['balanceAfterTransaction'] as num? ?? 0) : 0;

            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: PulseTopBar(title: 'My Ledger', subtitle: 'All bill & payment activity', leading: BackButton(color: t.fg2)),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverToBoxAdapter(
                    child: Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: balance > 0 ? t.dangerSoft : t.successSoft, borderRadius: BorderRadius.circular(PulseTokens.radius)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Current balance', style: TextStyle(fontSize: 11.5, color: (balance > 0 ? t.danger : t.success).withOpacity(0.8), fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text(inr(balance), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: balance > 0 ? t.danger : t.success)),
                        ],
                      ),
                    ),
                  ),
                ),
                if (entries.isEmpty)
                  const SliverToBoxAdapter(child: PulseEmptyState(illo: PulseIllo.noData, title: 'No ledger entries yet'))
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                    sliver: SliverList.separated(
                      itemCount: entries.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final e = entries[i] as Map;
                        final isCredit = e['type'] == 'Credit';
                        final date = DateTime.tryParse('${e['date']}');
                        final amount = (e['amount'] as num?) ?? 0;
                        return PulseCard(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('${e['description'] ?? ''}', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: t.fg1)),
                                    if (date != null)
                                      Text('${date.day}/${date.month}/${date.year}', style: TextStyle(fontSize: 11.5, color: t.fg4)),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('${isCredit ? '−' : '+'}${inr(amount)}', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: isCredit ? t.success : t.danger)),
                                  PulsePill(label: isCredit ? 'Credit' : 'Debit', tone: isCredit ? PulseTone.credit : PulseTone.debit, small: true),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
```

Update the file's doc comment (was describing the client-derived approximation) to:

```dart
/// Port of ui_kits/member-v2 `ScreensMore.jsx` `LedgerScreen`, now backed by
/// the real `GET /v1/ledger` endpoint (see
/// `apps/mobile-backend/src/modules/ledger/ledger.controller.ts`), which
/// reads the actual `transactions` collection instead of this page deriving
/// approximate debit/credit rows from `/bills` client-side.
```

- [ ] **Step 2: Run static analysis**

Run: `flutter analyze lib/features/member/ledger_page.dart`
Expected: no errors

- [ ] **Step 3: Commit**

```bash
git add apps/mobile-app/lib/features/member/ledger_page.dart
git commit -m "feat(app): Ledger page reads the real GET /ledger endpoint"
```

---

### Task 15: Flutter — Receipts page rewritten to `GET /receipts` + real PDF download

**Files:**
- Modify: `apps/mobile-app/lib/features/member/receipts_page.dart`

**Interfaces:**
- Consumes: `GET /v1/receipts` response shape from Task 7, `renderReceiptPdf` (Task 12).

- [ ] **Step 1: Replace the fetch + rendering + download logic**

Replace the entire body of `apps/mobile-app/lib/features/member/receipts_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dio/dio.dart';
import 'package:printing/printing.dart';
import '../../core/widgets/async_view.dart';
import 'pulse/pulse.dart';
import 'pulse/bill_pdf.dart';
import 'bills_page.dart' show inr;

/// Port of ui_kits/member-v2 `ScreensMore.jsx` `ReceiptsScreen`, now backed
/// by the real `GET /v1/receipts` endpoint (see
/// `apps/mobile-backend/src/modules/receipts/receipt.controller.ts`), which
/// reads the actual `receipts` collection instead of this page deriving one
/// fake receipt per paid bill client-side. "Download" produces a real PDF
/// via `renderReceiptPdf`.
class ReceiptsPage extends StatelessWidget {
  const ReceiptsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.pulse;
    final dio = context.read<Dio>();
    return Scaffold(
      backgroundColor: t.canvas,
      body: SafeArea(
        child: AsyncView<List>(
          fetch: () async => (await dio.get('/receipts')).data as List,
          builder: (context, receipts) {
            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: PulseTopBar(title: 'Receipts', subtitle: 'Payment receipts for your flat', leading: BackButton(color: t.fg2)),
                ),
                if (receipts.isEmpty)
                  const SliverToBoxAdapter(child: PulseEmptyState(illo: PulseIllo.noData, title: 'No receipts yet'))
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                    sliver: SliverList.separated(
                      itemCount: receipts.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final r = receipts[i] as Map;
                        final amount = (r['amount'] as num?) ?? 0;
                        final receiptNo = '${r['receiptNo'] ?? '—'}';
                        final periodLabel = '${r['periodLabel'] ?? ''}';
                        final date = DateTime.tryParse('${r['paidAt']}');
                        return PulseCard(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(color: t.brandSoft, borderRadius: BorderRadius.circular(11)),
                                child: Icon(Icons.receipt_long_rounded, color: t.brand, size: 18),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(receiptNo, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: t.fg1)),
                                    Text(
                                      '$periodLabel${date != null ? ' · ${date.day}/${date.month}/${date.year}' : ''}',
                                      style: TextStyle(fontSize: 11.5, color: t.fg4),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(inr(amount), style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: t.fg1)),
                                  GestureDetector(
                                    onTap: () async {
                                      final bytes = await renderReceiptPdf(r, periodLabel: periodLabel, formatInr: inr);
                                      await Printing.layoutPdf(onLayout: (_) async => bytes, name: '$receiptNo.pdf');
                                    },
                                    child: Text('Download', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: t.brand)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Run static analysis**

Run: `flutter analyze lib/features/member/receipts_page.dart`
Expected: no errors

- [ ] **Step 3: Commit**

```bash
git add apps/mobile-app/lib/features/member/receipts_page.dart
git commit -m "feat(app): Receipts page reads the real GET /receipts endpoint, downloads a real PDF"
```

---

### Task 16: Full-suite verification, manual walkthrough, and docs cleanup

**Files:**
- Modify: `apps/mobile-app/MEMBER_V2_GAPS.md`

**Interfaces:** none (verification + documentation task).

- [ ] **Step 1: Run the full backend suite**

Run (from `apps/mobile-backend`): `npm run test:coverage`
Expected: all tests pass; coverage thresholds met.

- [ ] **Step 2: Run the full backend typecheck**

Run (from `apps/mobile-backend`): `npm run typecheck`
Expected: no errors.

- [ ] **Step 3: Run the full Flutter test suite**

Run (from `apps/mobile-app`): `flutter test`
Expected: all tests pass, including the pre-existing `test/widget/`, `test/unit/`, `test/golden/` suites (none of this plan's edits touch their subject widgets/functions except through the now-passing helpers).

- [ ] **Step 4: Run the full Flutter analyzer**

Run (from `apps/mobile-app`): `flutter analyze`
Expected: no new errors introduced by this plan (pre-existing warnings elsewhere in the repo are out of scope).

- [ ] **Step 5: Manual walkthrough on an emulator/device**

Use the project's `run` skill (or `flutter run`) to launch `apps/mobile-app` against a local `apps/mobile-backend` seeded from `mongo_export/` (or any dataset with a Member linked to the logged-in User's `profile.memberId`), log in as a Member, and walk every screen this plan touched:
- Home: greeting shows a real name, not a `gs_...` username; hero card period is never "null"/"undefined".
- Bills: every card's top label is a real month/year, never "null"; tapping a bill opens Bill Detail with a real title.
- Bill Detail → "View full bill": Owner/Flat/Area are filled in (not "—"), header shows the real society name; "Save PDF" opens a real PDF; "Share" shares a real PDF file.
- Profile: name is real; Flat details shows Type/Ownership/Carpet area/Voting rights; Parking shows chips (or "Not available yet" if genuinely empty); Family members lists each person; Emergency contact still correctly shows "Not available yet" (no fabricated data).
- Ledger (via Home → quick actions → Ledger): real transaction rows, correct running balance.
- Receipts (reachable the same way Ledger is, or via a direct route if one exists): real receipt rows; "Download" produces an actual PDF.

Fix anything visually broken (overflow, truncation, wrong color) found during this pass directly in the relevant file from Tasks 8-15 before proceeding — this is the "missing UI/UX" pass the plan's goal references; the wiring tasks above should have already produced a polished result matching `.ui-craft/design-decisions.md`, so this step is a verification gate, not new design work.

- [ ] **Step 6: Update `MEMBER_V2_GAPS.md` to mark resolved gaps**

In `apps/mobile-app/MEMBER_V2_GAPS.md`, replace the "Data model mismatches" table row for "Profile rich fields" and the "No backend endpoint" bullets for Ledger/Receipts to reflect that they're now resolved — add a note at the top of the file:

```markdown
# Member V2 Design Port — Backend/Data Gaps

**Status update (see `docs/superpowers/plans/2026-07-12-member-data-ui-fill.md`):**
Ledger, Receipts, and Profile's rich fields (flatType, carpetAreaSqft,
ownershipType, hasVotingRights, parkingSlots, familyMembers, whatsappNumber)
are now backed by real endpoints/data — `Member`/`Society`/`Transaction`/
`Receipt` models were added to `apps/mobile-backend/src/models/index.ts`,
reading the real `members`/`societies`/`transactions`/`receipts`
collections. Bill PDF export uses the real `billHtml` field (falling back to
a server-synthesized one). Remaining known gaps below are still accurate:
notice acknowledge has no backend call, and Profile's "Emergency contact"
has no backing field on `Member` at all (not fabricated).

Concrete gaps found while porting `ui_kits/member-v2` (see
`MEMBER_V2_DESIGN_PORT.md` for what shipped). Actionable follow-up list for
whoever picks up backend work next — separate from the design-port narrative
so it doesn't get lost in there.
```

Leave the rest of the file's content as historical record (the "If you pick this up" section's context is still accurate for what remains: notice-acknowledge, and any future decision on adding a real Emergency Contact field to `Member`).

- [ ] **Step 7: Commit**

```bash
git add apps/mobile-app/MEMBER_V2_GAPS.md
git commit -m "docs: mark Ledger/Receipts/Profile data gaps resolved"
```
