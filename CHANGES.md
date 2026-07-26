# AapliSociety app — what changed

Copy these files over the same paths in your Flutter repo. No `pubspec.yaml`
changes are needed — `url_launcher`, `image_picker` and `image` were already
declared.

## 1. New Tenancy UI (ported from the Owner App mockup)

Only the three screens you asked for were taken from the mockup — **My Tenant**,
**Manage Tenants**, **Rent Payments** — plus the tenant-side environment. Nothing
else from the mockup was pulled in.

| File | Status |
|---|---|
| `lib/features/tenant/tenant_ui.dart` | new — shared tenancy widget kit |
| `lib/features/tenant/my_tenant_page.dart` | rewritten |
| `lib/features/tenant/manage_tenants_page.dart` | rewritten (Add tenant / Past tenant history tabs) |
| `lib/features/tenant/rent_payment_page.dart` | rewritten (hero total, record form, filtered history) |
| `lib/features/tenant/tenant_detail_sheet.dart` | new — detail sheet for active/request/past |
| `lib/features/tenant/tenant_profile_page.dart` | new — the tenant environment |
| `lib/features/tenant/tenant_api.dart` | appended: `updateTenantLogin`, `fetchMyTenancy`, `uploadTenantDocumentBytes` |
| `lib/features/member/member_profile_page.dart` | rewritten — tenancy section added, role-aware |

The mockup's design tokens matched `PulseTokens` exactly, so **no theme values
were changed** — the port reuses your existing design system rather than adding
a second one.

### Profile page is now the entry point
Profile is grouped into **Account / My tenancy / Preferences / Emergency**.
"My tenancy" holds My tenant, Manage tenants and Rent payments. Owners see the
management rows; a member whose `occupancyType == 'Tenant'` gets
`TenantProfilePage` instead — read-only tenancy facts, a submit-rent form, their
own payment history, document status, and their flat owner's contact. Tenants
cannot see or reach the owner-only management screens.

## 2. Fixes from the audit plan (through Phase 6)

**P0 — `/ledger` rendered as yellow-underlined monospace.**
`ledger_page.dart` returned `SafeArea > Column` with no `Scaffold`, so with no
`Material` ancestor every `Text` fell back to Flutter's error style. Now wrapped
in a `Scaffold` on the themed canvas.

**P0 — visitor photos never reached R2.** See `CHANGES.md` in the web zip; the
id was read from the wrong key, so the upload call was skipped silently.
`_extractVisitorId()` now accepts every shape, and a missing id is reported.

**P1 — internal errors shown to residents.** Removed from `visitors_page.dart`
and `new_entry_tab.dart`:
- `Photo captured (key: ...) but no signed URL returned — R2 read/signing failed.`
- `No photo was uploaded to R2 for this visitor.`
- `No guard number on this entry — backend did not send guardPhone/gatePhone.`

Replaced with plain language that tells the resident what to do instead.

**P1 — UI froze during photo capture.** `image_compress.dart` decoded and
re-encoded multi-megapixel JPEGs on the UI isolate. Now runs inside `compute()`.

**Consistency (Phase 5–6).**
- `lib/core/utils/formatters.dart` — one source of truth for money, dates,
  month grouping and relative time. Killed the per-file `_fmtDate` copies.
- `lib/core/widgets/pulse_scaffold.dart` — `PulseScaffold`, `PulseSectionLabel`,
  `PulseGroup`, `PulseRow` so every pushed page has a Material ancestor, a back
  affordance and consistent padding by construction.
- `lib/core/widgets/pulse_field.dart` — labelled fields with real inline
  validation, plus money and month variants.
- `lib/core/widgets/hold_to_confirm.dart` — SOS is hold-to-confirm (2s,
  escalating haptics) instead of a single tap; destructive actions use a
  weighted Cancel/Confirm pair.
- All amounts use tabular figures so columns line up.
- Tap targets on the new screens are ≥ 44–48dp; every icon-only control has a
  semantic label; both themes were checked.

## 3. Router

- `/manage-tenants` accepts `extra: {'tab': 'past'}` to deep-link the history tab.
- `/tenant-profile` added.
- `/add-tenant` and `/tenant-history` still resolve, so existing deep links and
  notification payloads keep working.

## ⚠️ Release blocker (not fixed — needs your decision)

The Android application id is still **`com.example.aapli_society`**. Google Play
rejects `com.example.*`. Changing it requires a new package id, a matching
`google-services.json`, and re-issuing the FCM registration — so I left it for
you rather than silently breaking push.
