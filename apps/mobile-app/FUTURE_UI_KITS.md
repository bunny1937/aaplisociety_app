# Future UI Kits — Not Built This Pass

The design handoff bundle (`AapliSocietyy Design System-handoff.zip`,
`aaplisocietyy-design-system/project/ui_kits/`) contains five surfaces
beyond `member-v2`, which is the only one this pass implemented (see
`MEMBER_V2_DESIGN_PORT.md`). Catalogued here so the scope decision is
explicit and the design work isn't lost — none of this exists in the
Flutter app or the Node backend yet.

The zip is not part of this repo; ask whoever ran the original design-port
session for it, or re-export from the Claude Design project if unavailable.

## `ui_kits/admin` — Web admin dashboard

Sidebar (260px fixed) + sticky top header shell. Login, Dashboard (stat
grid, Quick Actions, Recent Payments/Ledger), View Bills (thumbnail grid +
full bill modal). **This repo has no web app at all** — `apps/` only
contains `mobile-app` (Flutter) and `mobile-backend` (Node). Building this
means starting a new Next.js/React app from scratch, not porting into an
existing one. Source data in the design kit is hard-coded; would need to be
wired to the same `mobile-backend` API the Flutter app already uses.

## `ui_kits/guard` — Guard/security app

Login, Dashboard, New Entry (visitor logging), Verify Log. Maps to the
Flutter app's existing `lib/features/security/` surface
(`security_shell.dart`), which is real and wired today with its own
"Ledger" visual language, structurally similar to what the member surface
looked like before this pass. Would need the same kind of treatment: read
`GuardScreensAuth.jsx`, `GuardScreensDashboard.jsx`, `ScreensNewEntry.jsx`,
`ScreensVerifyLog.jsx`, `GuardPrimitives.jsx`, `GuardData.js` in full before
starting (same "read top to bottom, follow imports" approach used for
member-v2).

## `ui_kits/superadmin` — Platform-owner dashboard

Login (email + password + admin key), Dashboard (Platform Pulse hero,
society status breakdown), Societies list, Society detail sheet (stats,
credentials, suspend/delete). Notably fixes a real security anti-pattern in
the source codebase the design was distilled from: plaintext admin
passwords rendered in a table column. The redesign moves credentials behind
a masked "Reveal" + copy-to-clipboard pattern in the detail sheet and
recommends migrating to one-time-token resets. **Worth flagging to whoever
owns the actual superadmin surface**, independent of whether this UI kit
ever gets built — if plaintext passwords are rendered anywhere in the real
product today, that's a security issue regardless of design system status.

## `ui_kits/revamp` — Cross-surface admin/superadmin explorations

`AdminViews.jsx`, `SuperAdminViews.jsx`, `Shell.jsx`, plus a
`tweaks-panel.jsx` (looks like an in-browser design-tweaking tool, not
product UI). Appears to be an earlier or alternate exploration of the admin
kit rather than a distinct target — check with whoever ran the design
session which of `admin/` vs `revamp/` is authoritative before building
from it.

## `ui_kits/member` (v1) — Superseded

An earlier member-app design iteration, explicitly superseded by
`member-v2` (the one this pass implemented). Its own README calls out that
it "mocks the Flutter look" by rendering the Next.js codebase's responsive
web pages inside an iOS frame, since the Flutter source wasn't attached at
the time it was made. **member-v2 is the current one — don't build from
this.** Kept in the bundle for historical reference only.

## If picking any of these up

Same process as member-v2: read the kit's `index.html` in full top to
bottom first, follow its imports (Primitives/Icons/Data/Screens files),
recreate pixel-perfect in whatever's idiomatic for the target codebase
(don't copy the HTML/React/CSS structure literally), and check real
backend data shapes against the kit's fixture data before wiring — the
member-v2 pass found real/fixture mismatches in nearly every data model
(see `MEMBER_V2_GAPS.md`); expect the same here.
