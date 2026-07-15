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

## No backend endpoint

- **Ledger** (`GET /ledger` or similar) — a `Payment` document is already
  created server-side on every `POST /bills/:id/pay`
  (`apps/mobile-backend/src/modules/bills/bill.controller.ts`), but nothing
  lists them. `ledger_page.dart` derives entries client-side from `/bills`
  alone (one debit row per bill, one credit row per bill with
  `amountPaid > 0`, both dated at the bill's `dueDate` since no finer date
  is available). A real endpoint would give exact per-transaction
  dates/modes instead of this approximation.
- **Receipts** (`GET /payments` or similar) — same root cause.
  `receipts_page.dart` derives one receipt per paid bill; "Download" toasts
  instead of producing a real file.
- **Bill PDF** — `bill_format_sheet.dart`'s "Save PDF" toasts rather than
  generating/downloading a real file. If a backend-rendered bill PDF exists
  under a different endpoint, wire it up; otherwise this needs either a new
  backend endpoint or a client-side PDF package (`pdf`/`printing`, not in
  `pubspec.yaml` today).
- **Notice acknowledge** — the design's "✋ Acknowledge this notice" button
  is local-only state in `notices_page.dart` (matches the design mock,
  which also has no ack call). No `POST /notices/:id/ack` exists.

## Data model mismatches (fixture vs real)

| Area | Design fixture (`MemberV2Data.js`) | Real (`packages/shared-types`, controllers) | Resolution taken |
|---|---|---|---|
| Notice type | Fixed enum: security/water/meeting/maintenance/event/… | `Notification.type` / app's `tag` field: free text, no enum | Kept dynamic tag filtering; emoji mapped by substring match, falls back to 📢 |
| Notice priority | `low/medium/high/urgent` | `low/normal/high/urgent` ("normal" not "medium") | Used real value; "urgent"/"high" both treated as attention-worthy |
| Complaint status | `PENDING/APPROVED/REJECTED/CLOSED/EXPIRED` | `Open/In progress/Resolved/Rejected` | Used real vocabulary throughout |
| Complaint category | 10 values incl. cleanliness/billing/staff/pets | App's existing 6: maintenance/water/parking/security/noise/other | Kept the 6 real categories — the 10-category picker was **not** verified against a real validation schema, don't widen without confirming the backend accepts the extra 4 |
| Visitor "offline confirm" | `VISITORS_CONFIRM` with `offlineMeta.note` | No such field on `Visitor` (`packages/shared-types/src/models.ts`) | Tier omitted entirely from `visitors_page.dart` — do not fake it |
| Profile rich fields | `flatType`, `carpetAreaSqft`/`builtUpAreaSqft`, `ownershipType`, `possessionDate`, `hasVotingRights`, `parkingSlots[]`, `familyMembers[]`, `emergencyContact`, `whatsappNumber` | None exist on `User`/`Profile` | UI built and shows "Not available yet" per user decision — needs real backend fields + endpoint before it can populate |
| Bill `previousBalance` | Present on fixture, drives a warning banner in Bill Format | Not on the real `Bill` model | Banner only renders if the field happens to be present in the API response (defensive, currently always absent) |

## Dark mode

The design handoff has **zero dark tokens** — `MemberV2Primitives.jsx`
`ThemeStyles()` only defines light `--m-*` values, and `colors_and_type.css`
doesn't cover the member-v2 token set at all. `PulseTokens.dark`
(`pulse_tokens.dart`) is an extrapolation kept in the same spirit as the
light set, not a literal design value — if a real dark-mode design ever
ships, reconcile it against this file rather than assuming it matches.

## If you pick this up

Priority order if scoping backend work from this list: (1) a payments-list
endpoint unblocks both Ledger and Receipts with real data in one shot, (2) a
notice-type enum lets the Notices filter match the design's fixed
5-category intent instead of free-text tags, (3) Profile's rich fields are
the largest single gap but also the most product-decision-dependent (do
parking slots/family members/emergency contact even belong on this
platform's roadmap?) — confirm scope before building the backend for it.
