# Post-Production Monitoring & Triage

How Tulanam is watched after deployment, and the running log of what's been found.

## Two layers

1. **Always-on (server, no human/Claude needed)** — `errorReportDigest` (deployed,
   asia-south1, runs every 24h) emails a grouped summary of the last 24h of
   `error_reports` and prunes old entries. This runs whether or not anyone is in a
   session. It is the safety net.

2. **Claude triage ritual (this file)** — deeper analysis that the server digest
   can't do: reproduce, cross-reference code, propose/ship fixes. Runs whenever a
   Claude Code session is active (a session-scoped cron nudges it; see below).

## The ritual (run each pass)

```bash
tool/triage_errors.sh        # grouped digest of current error_reports (read-only)
```

1. Run the script. Compare signatures against the **Log** below.
2. For each NEW or worsening signature: open the implicated file (stack top), confirm
   it's real, reproduce mentally, decide fix vs watch.
3. Fix highest `count × severity` first. Fatal > non-fatal. Ship as `fix:` commits so
   the version auto-bumps.
4. Append an entry to the Log with date, signature, verdict, action. Mark resolved
   ones so they're not re-triaged.
5. Also skim Firebase: Functions logs for `severity>=ERROR`, and any user-reported
   issues the user forwards.

> Scheduling reality: `CronCreate` only fires while a Claude Code session is open and
> auto-expires after 7 days. It is a *nudge*, not guaranteed unattended monitoring —
> the server digest (layer 1) is the real always-on guarantee. Re-arm the cron each week.

## Sources of signal
- `error_reports` Firestore collection (client crashes/uncaught errors — `tool/triage_errors.sh`).
- `errorReportDigest` daily email (`GMAIL_EMAIL`).
- Cloud Functions logs: `gcloud functions logs read <fn> --region=asia-south1 --project=tulanam`.
- User-forwarded reports.

---

## Triage Log

### 2026-06-12 — baseline (first run)
- **`Bad state: Cannot add new events after calling close`** — `_BroadcastStreamController.add`
  (dart:async). **4× FATAL**, macos. **RESOLVED (in code; ships next build).**
  Root cause: `TrafficSignalService.dispose()` (traffic_signal_service.dart:319) called
  `disconnect()` without `await`, then closed `_stateController`; the in-flight async
  `disconnect()` resumed and `_setState()` → `add()` on the closed controller. Fix:
  guard `_setState` with `if (_stateController.isClosed) return;` (also covers late
  socket callbacks). _(Surfaced + fixed on the very first triage run.)_

### 2026-06-13 — scheduled pass DEFERRED
`tool/triage_errors.sh` returned no data because the `tech@tulanam.com` gcloud token
expired mid-session (during the macOS Firebase Auth keychain debugging). No triage
performed. Resume after re-auth (`gcloud auth login tech@tulanam.com`). Not a code/app
issue — purely the local CLI credential.

### 2026-06-13 — pass complete (re-run after re-auth)
2 signatures, both known/non-actionable: (1) `StreamController add-after-close` — already
RESOLVED in source (ships next build); (2) 2× `permission-denied` — STALE, from the reverted
Stage-3 rule attempts (00:05/00:31), not the now-live working rules. No new bugs.
