# pinHash relocation — AS BUILT (implemented 2026-06-11)

**Status: IMPLEMENTED** (compile-clean; `operator_pins` rule emulator-validated).
Deploy + verify unlock on your machine (it's your own staging). The dual-read
fallback means `verifyOperatorPin` cannot break mid-migration.

## What it does
`pinHash = sha256(pin + email)` was stored on the **client-readable** operator doc
(4-6 digit PIN → offline brute-force). It now lives in the **server-only**
`operator_pins/{companyId}__{emailLower}` collection; the operator doc carries only a
non-sensitive `hasPin: true` flag.

## How it works (no registration rewrite — lower risk)
- **`operator_pins`** — server-only (`firestore.rules: if false`). Value `{ pinHash, companyId, email, updatedAt }`.
- **`verifyOperatorPin`** reads `operator_pins` **first** (`_readPinHash`), falling back to
  the doc hash — both the fast path and the all-operators scan path. So unlock works
  whether or not a given operator has been relocated yet.
- **`setOperatorPin` / `resetOperatorPin`** write the hash to `operator_pins` + set `hasPin`
  and **strip** the doc hash (`_writePinHash`, `stripDoc` default true).
- **Registration is UNCHANGED** (still writes `pinHash` to the doc) — deliberately, to avoid
  breaking new-operator PIN setup. The hash is relocated automatically by:
  - **`sweepPinHashes`** — scheduled **hourly** (`functions.pubsub.schedule`), collectionGroup
    over every operator (nested / site / flat), `_relocatePinFromDoc` moves any doc hash into
    `operator_pins` and deletes it. So a freshly-registered operator's hash is client-readable
    for **at most ~1 hour**.
  - **`migratePinHashes(companyId)`** — admin callable, same relocation for one company,
    immediate. Optional (the sweep covers it); use it to backfill now instead of waiting.
- **Client existence-checks** (`operators_screen` "_hasPinSet", `profile_screen`) use
  `hasPin == true || pinHash != null` (the `|| pinHash` covers the pre-sweep window; it can be
  dropped a release later).
- `_relocatePinFromDoc` (sweep/migrate) **never overwrites an existing `operator_pins` entry** —
  it only fills a gap then strips the doc. `operator_pins` is authoritative (a PIN change writes
  it directly), so this prevents a PIN change from silently reverting to a stale doc copy on the
  next sweep (e.g. a site-operator doc that `setOperatorPin`'s email-query strip missed). It
  writes `operator_pins` before deleting the doc hash, so a failure can't leave an operator pin-less.
- Pre-existing (not changed here): `verifyOperatorPin`'s find-logic covers nested + flat operators,
  not `sites/{s}/operators`; if any PIN-using operators live only under sites, that gap predates
  this work.

## Deploy / operate
1. `firebase deploy --only functions,firestore:rules` + rebuild/ship the client.
2. Nothing else required — `sweepPinHashes` relocates all existing + new hashes within an hour.
   (Want it immediate? Invoke `migratePinHashes({companyId, sessionToken})` once as an admin.)
3. **Verify unlock** after deploy: lock the app, unlock with an existing operator's PIN (reads
   `operator_pins` after sweep, or the doc fallback before it). Set + reset a PIN → unlock OK,
   and the operator doc shows `hasPin: true` and **no `pinHash`**.

## Rollback
- `verifyOperatorPin` reading new-first is additive — to revert behavior, change `_readPinHash`
  back to `operatorDoc.data().pinHash`. But once `sweepPinHashes`/`migratePinHashes` has stripped
  the doc hashes, the data lives only in `operator_pins`, so **export the operator collections
  before the first sweep** if you want a restore point. To pause stripping, disable
  `sweepPinHashes` and don't call `set/resetOperatorPin`.

## Notes
- `verifyOperatorPin`'s `pin_throttle` (online brute-force lock) is unchanged.
- The hourly sweep reads all operators each run but only writes the few that still carry a doc
  hash; after the first sweep it's a cheap no-op until a new operator registers.
- Site operators set via `setOperatorPin` get `operator_pins` written immediately (authoritative
  for verify) and the stale site-doc hash stripped by the next sweep.
