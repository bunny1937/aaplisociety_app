# Member V2 Design Port — "Pulse Mobile"

Record of the member-surface UI revamp that ported the Claude Design handoff
bundle (`AapliSocietyy Design System-handoff.zip`, `ui_kits/member-v2`) into
this Flutter app. Read this before touching member-surface UI again.

## What changed

The member surface (`lib/features/member/*`, `lib/features/auth/login_page.dart`,
`lib/features/complaints/complaints_page.dart`) was fully re-skinned from the
app's original "Ledger" visual language (navy/cream, Fraunces + Manrope +
IBM Plex Mono, glassmorphism) to the design handoff's "Pulse Mobile" system
(Inter-only, cool blue/white flat cards, iOS-style bottom sheets, Lucide-style
icons). Every screen's real API calls, socket listeners, bloc wiring, and
error handling were preserved — only the visual layer and, in a few
documented cases, the navigation shape changed.

Admin, guard, superadmin, security, and splash surfaces were **not** touched
— out of scope for this pass. See `FUTURE_UI_KITS.md`.

## Token layer

`lib/features/member/pulse/pulse_tokens.dart` — a `ThemeExtension<PulseTokens>`
ported from the design's `--m-*` CSS custom properties
(`MemberV2Primitives.jsx` `ThemeStyles()`), registered on both
`AppTheme.light()` and `AppTheme.dark()` via `extensions: [...]`. Access with
`context.pulse` (e.g. `context.pulse.brand`).

The design handoff shipped **light tokens only**. The dark set in
`PulseTokens.dark` is an extrapolation in the same spirit, not a literal
handoff value — see `MEMBER_V2_GAPS.md`.

Radii: 10 / 18 / 26 (`PulseTokens.radiusSm/radius/radiusLg`). Two shadow
presets (`shadowCard`, `shadowPop`). Font is Inter via the `google_fonts`
package already in `pubspec.yaml`.

## Shared widget library

`lib/features/member/pulse/` — all new, ported from `MemberV2Primitives.jsx`:

| File | Widget | Notes |
|---|---|---|
| `pulse_button.dart` | `PulseButton` | 6 variants, 3 sizes, press-scale to 0.96 |
| `pulse_pill.dart` | `PulsePill` | status tone → color; `overdue` tone pulses |
| `pulse_card.dart` | `PulseCard` | tappable variant scales to 0.98 |
| `pulse_avatar.dart` | `PulseAvatar` | initials, deterministic hue, optional `SweepGradient` ring |
| `pulse_skeleton.dart` | `PulseSkeleton` | shimmer via `ShaderMask` + `AnimationController` |
| `pulse_topbar.dart` | `PulseTopBar`, `PulseIconButton` | large-title header + badge icon button |
| `pulse_sheet.dart` | `showPulseSheet()` | wraps `showModalBottomSheet`, drag handle, optional title+close |
| `pulse_segmented.dart` | `PulseSegmented<T>` | horizontally-scrolling filter pills |
| `pulse_search_field.dart` | `PulseSearchField` | built for completeness, not yet wired to a screen |
| `pulse_progress_ring.dart` | `PulseProgressRing` | `CustomPainter` arc, animates on mount |
| `pulse_illustrations.dart` | `PulseIllustration`, `PulseEmptyState` | 6 hand-drawn illustrations as `CustomPainter`s (no SVG assets) |
| `pulse_spinner.dart` | `PulseSpinner` | |
| `pulse_toast.dart` | `showPulseToast()` | separate from the app-wide `showAppToast` (admin/security keep the old ink/paper toast) |
| `notice_emoji.dart` | `emojiForNoticeType()` | shared by Dashboard + Notices |

Reused rather than reinvented: `PressEffect`-style tap-scale pattern,
`AsyncView<T>` (loading/error/empty/retry boilerplate), `Haptics`,
`LedgerSheetHandle`'s concept (own `PulseSheet` chrome instead, same idea).

## Per-screen notes

- **Login** (`features/auth/login_page.dart`) — light Pulse look replaces the
  old dark-glass treatment (design explicitly wants light). Real
  phone-or-username field + `AuthBloc` dispatch kept; password show/hide
  added. "Forgot password?" renders inert, matching the mock (no backend
  handler exists).
- **Dashboard** (`dashboard_page.dart`) — avatar+ring header, gradient hero
  with `PulseProgressRing`, conditional "needs attention" gate card, 4-up
  quick actions, 2-up account snapshot (₹ outstanding / ₹ paid this year),
  latest-notices preview. Cross-tab navigation (quick actions, notice bell,
  hero buttons) uses `memberTabNotifier` (`member_shell.dart`), the same
  `ValueNotifier` pattern as `theme_controller.dart`'s `themeModeNotifier`.
- **Bills** (`bills_page.dart`) — 2-up gradient-thumbnail grid replaces the
  old single-column list. 4-way filter (All/Overdue/Partial/Paid) using the
  real `BILL_STATUS.OVERDUE` value plus a due-date fallback
  (`effectiveStatus()`), not the design fixture's status vocabulary.
- **Bill Detail** (`pulse/bill_detail_sheet.dart`) — now a `PulseSheet` with
  itemized breakdown from `Bill.charges` (real field, wasn't surfaced
  before), Paid/Balance summary, "View full bill" → Bill Format sheet, Pay →
  Make Payment sheet.
- **Bill Format** (`pulse/bill_format_sheet.dart`) — new, no prior
  equivalent. "Save PDF" toasts rather than producing a real file — no
  backend bill-PDF endpoint exists (see `MEMBER_V2_GAPS.md`); Share uses the
  real `share_plus` package.
- **Make Payment** (`pulse/payment_sheet.dart`) — converted from a routed
  page to a 3-stage (`select`/`processing`/`success`) `PulseSheet` chained
  off Bill Detail, per explicit user decision. Same real
  `POST /bills/:id/pay` + error handling as before. The old standalone
  `/payment` route and `payment_page.dart` were removed as fully superseded.
- **Notices** (`notices_page.dart`) — urgent-first section + local-only
  acknowledge flow (design has no backend ack call either). Kept the app's
  dynamic tag-derived filtering (real `Notification.type`/`tag` is free
  text, no fixed enum) restyled as `PulseSegmented` pills, with emoji from
  the handoff README's iconography table where a tag matches.
- **Complaints** (`features/complaints/complaints_page.dart`) — real
  6-category list and real status vocabulary (Open/In progress/
  Resolved/Rejected), not the design fixture's 10 categories / 5-value
  enum. Admin/secretary inline status-management branch (status cycling,
  resolution note, `LedgerTimeline`) kept — no design equivalent, per user
  decision.
- **Visitors** (`visitors_page.dart`) — merged from the old two-page split
  (`visitors_page.dart` pre-register form + `visitor_history_page.dart`
  approve/deny history, now deleted). New 3-tier layout: "at the gate now"
  (Pending, Allow/Deny), "all clear" empty state, "today's visitors" log.
  The design's reactive-only screen has no pre-register form; kept the real
  feature per user decision, moved behind a "+" FAB sheet. The design's
  "offline confirm" tier was **not** built — no backing field exists on the
  real `Visitor` model.
- **Profile** (`member_profile_page.dart`) — gradient header + stacked info
  sections matching the design exactly, with "Not available yet"
  placeholders for fields the backend doesn't have yet (see
  `MEMBER_V2_GAPS.md`), per user decision. Old navigation tiles (Change
  password, My complaints, dark-mode toggle) folded in below the info
  sections; "Account details" and "Visitor history" tiles were dropped —
  their content now lives inline (Flat/Contact sections) or on the Visitors
  tab directly.
- **Ledger** (`ledger_page.dart`) and **Receipts** (`receipts_page.dart`) —
  both new, no prior equivalent, both derived client-side from `/bills`
  since no backend endpoint lists individual `Payment` records. See
  `MEMBER_V2_GAPS.md` for what a real endpoint would improve.

## Navigation changes

- Bottom tab order changed to match the design: Home / Bills / Notices /
  Visitors / Profile (was Home / Bills / Visitors / Notices / Profile).
- `memberTabNotifier` (`member_shell.dart`) lets nested pages switch tabs
  without a shell `BuildContext` handle.
- `/ledger` and `/receipts` added as pushed `go_router` routes.
- `/payment` and `/visitor-history` routes removed (superseded — see above).
