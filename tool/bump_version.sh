#!/usr/bin/env bash
# Conventional-Commits version bump for Tulanam.
#
#   PATCH (0.0.X) = bug fixes   -> commits prefixed `fix:`
#   MINOR (0.X.0) = features    -> commits prefixed `feat:`
#   MAJOR (X.0.0) = PUBLIC LAUNCH ONLY -> never automatic; run with --launch
#
# Semver positions are independent integers (no odometer carry: 0.0.9 + fix = 0.0.10).
# A higher bump resets everything to its right. The +build counter always increments.
# While MAJOR == 0 (pre-launch) a breaking change only bumps MINOR — 0.x may break.
#
# Usage:
#   tool/bump_version.sh                 # dry-run: show the bump it WOULD make
#   tool/bump_version.sh --apply         # write pubspec.yaml, commit, tag vX.Y.Z
#   tool/bump_version.sh --launch        # go public: 0.x -> 1.0.0 "Mundra" (dry-run)
#   tool/bump_version.sh --launch --apply
set -euo pipefail
cd "$(dirname "$0")/.."

# Port codenames by MAJOR version (Apple-style: name rides the major line).
codename_for() {
  case "$1" in
    1) echo "Mundra" ;; 2) echo "Kandla" ;; 3) echo "Vizag" ;;
    4) echo "Paradip" ;; 5) echo "Tuticorin" ;; 6) echo "Haldia" ;;
    *) echo "" ;;
  esac
}

APPLY=0; LAUNCH=0
for a in "$@"; do
  case "$a" in
    --apply) APPLY=1 ;; --launch) LAUNCH=1 ;;
    *) echo "unknown flag: $a"; exit 2 ;;
  esac
done

cur=$(grep -E '^version:' pubspec.yaml | head -1 | sed -E 's/version:[[:space:]]*//')
sem="${cur%%+*}"; build="${cur##*+}"
IFS='.' read -r MAJ MIN PAT <<<"$sem"
[ "$build" = "$cur" ] && build=0   # no +build present
newbuild=$((build + 1))

last=$(git describe --tags --match 'v*' --abbrev=0 2>/dev/null || echo "")
range="${last:+$last..}HEAD"
subjects=$(git log $range --format='%s%n%b' 2>/dev/null || echo "")

has_feat=0; has_fix=0; has_break=0
echo "$subjects" | grep -qiE '^feat(\(.+\))?!?:' && has_feat=1
echo "$subjects" | grep -qiE '^fix(\(.+\))?!?:'  && has_fix=1
echo "$subjects" | grep -qiE '!:|BREAKING CHANGE' && has_break=1

if [ "$LAUNCH" = 1 ]; then
  [ "$MAJ" -ne 0 ] && { echo "ERROR: already launched (v$sem). --launch is only for the 0.x -> 1.0.0 jump."; exit 1; }
  NMAJ=1; NMIN=0; NPAT=0; reason="PUBLIC LAUNCH"
elif [ "$MAJ" -eq 0 ]; then
  # Pre-launch: features/breaking -> MINOR, fixes -> PATCH, MAJOR frozen at 0.
  if [ "$has_feat" = 1 ] || [ "$has_break" = 1 ]; then
    NMAJ=0; NMIN=$((MIN + 1)); NPAT=0; reason="feature (pre-1.0 minor)"
  else
    NMAJ=0; NMIN=$MIN; NPAT=$((PAT + 1)); reason="fix/chore (patch)"
  fi
else
  # Post-launch: full semver.
  if [ "$has_break" = 1 ]; then NMAJ=$((MAJ + 1)); NMIN=0; NPAT=0; reason="breaking (major)"
  elif [ "$has_feat" = 1 ]; then NMAJ=$MAJ; NMIN=$((MIN + 1)); NPAT=0; reason="feature (minor)"
  else NMAJ=$MAJ; NMIN=$MIN; NPAT=$((PAT + 1)); reason="fix/chore (patch)"; fi
fi

newsem="$NMAJ.$NMIN.$NPAT"
name=$(codename_for "$NMAJ")
echo "current:  $cur"
echo "commits:  feat=$has_feat fix=$has_fix breaking=$has_break  (since ${last:-repo start})"
echo "decision: $reason"
echo "next:     $newsem+$newbuild${name:+  \"$name\"}"

if [ "$APPLY" != 1 ]; then
  echo ""; echo "(dry-run — re-run with --apply to write pubspec.yaml, commit, and tag)"
  exit 0
fi

sed -i.bak -E "s/^version:.*/version: $newsem+$newbuild/" pubspec.yaml && rm -f pubspec.yaml.bak
git add pubspec.yaml
git commit -m "chore(release): v$newsem${name:+ \"$name\"}" >/dev/null
git tag "v$newsem"
echo ""; echo "applied. tagged v$newsem — push the tag to trigger the release build:"
echo "  git push && git push origin v$newsem"
