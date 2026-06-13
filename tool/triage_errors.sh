#!/usr/bin/env bash
# Pull + group the tulanam `error_reports` (client crash/error log) for triage.
# Read-only. Output is a grouped digest for a human/Claude to reason over.
#
#   tool/triage_errors.sh            # group all current reports (collection is auto-pruned)
#   tool/triage_errors.sh --json     # raw JSON of the grouped result (for tooling)
set -euo pipefail
export PATH=/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin:$PATH

ACCOUNT=tech@tulanam.com
PROJECT=tulanam
TOKEN=$(gcloud auth print-access-token --account="$ACCOUNT" 2>/dev/null)
BASE="https://firestore.googleapis.com/v1/projects/$PROJECT/databases/(default)/documents"

TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
curl -s "$BASE/error_reports?pageSize=500" -H "Authorization: Bearer $TOKEN" 2>/dev/null > "$TMP"

DATA_FILE="$TMP" python3 - "$@" <<'PY'
import sys, os, json, collections
d = json.load(open(os.environ["DATA_FILE"]))
docs = d.get("documents", [])

def g(f, k, default=""):
    v = f.get(k, {})
    return v.get("stringValue") or v.get("timestampValue") or default

groups = collections.OrderedDict()
fatal_total = 0
for doc in docs:
    f = doc.get("fields", {})
    msg = g(f, "message") or "(no message)"
    sig = msg.split("\n")[0][:120]
    fatal = f.get("fatal", {}).get("booleanValue", False)
    if fatal:
        fatal_total += 1
    grp = groups.setdefault(sig, {"count": 0, "versions": set(), "platforms": set(), "fatal": 0, "last": "", "stack": ""})
    grp["count"] += 1
    grp["versions"].add(g(f, "version") or "?")
    grp["platforms"].add(g(f, "platform") or "?")
    if fatal:
        grp["fatal"] += 1
    ts = g(f, "createdAt")
    if ts > grp["last"]:
        grp["last"] = ts
    if not grp["stack"]:
        st = g(f, "stack").split("\n")
        grp["stack"] = (st[0] if st else "")[:140]

if "--json" in sys.argv:
    out = []
    for k, v in groups.items():
        row = {"signature": k}
        for kk, vv in v.items():
            row[kk] = sorted(vv) if isinstance(vv, set) else vv
        out.append(row)
    print(json.dumps(out, indent=2))
    sys.exit(0)

print("=== error_reports triage ===")
print("%d report(s) | %d distinct signature(s) | %d fatal\n" % (len(docs), len(groups), fatal_total))
if not docs:
    print("No error reports. Clean.")
    sys.exit(0)
for sig, v in sorted(groups.items(), key=lambda kv: -kv[1]["count"]):
    flag = "FATAL " if v["fatal"] else ""
    vers = ",".join(sorted(v["versions"]))
    plats = ",".join(sorted(v["platforms"]))
    print("[%3dx] %s%s" % (v["count"], flag, sig))
    print("        versions=%s platforms=%s last=%s" % (vers, plats, v["last"][:19]))
    if v["stack"]:
        print("        -> %s" % v["stack"])
print("\nTriage: confirm new/recurring vs MONITORING.md, reproduce, fix highest count*severity first.")
PY
