#!/usr/bin/env bash
# Replace the OLD Firebase project id + Storage bucket with the NEW one in the
# hardcoded CODE references.
#
#   Usage:  tool/rename_project.sh <new-project-id>
#
# Run this AFTER `flutterfire configure --project=<new-project-id>`. flutterfire
# regenerates firebase_options.dart, the GoogleService-Info.plist files,
# google-services.json and the firebase.json `flutter` block — those carry
# project-specific API keys, so this script deliberately does NOT touch them.
set -euo pipefail
cd "$(dirname "$0")/.."

NEW="${1:-}"
[ -z "$NEW" ] && { echo "usage: tool/rename_project.sh <new-project-id>"; exit 1; }
OLD="weighbridge-management"

FILES=(
  lib/shared/services/cloud_functions_service.dart
  functions/email_render.js
  functions/index.js
  functions/release_publish.js
  tool/publish_release.js
  .github/workflows/release.yml
  functions/seed.js
  functions/seed_full.js
  functions/seed_weighments.js
)

for f in "${FILES[@]}"; do
  [ -f "$f" ] || continue
  # Replace the bucket (longer, more specific) first, then the bare project id.
  perl -i -pe "s/\\Q${OLD}.firebasestorage.app\\E/${NEW}.firebasestorage.app/g; s/\\Q${OLD}\\E/${NEW}/g" "$f"
  echo "updated  $f"
done

echo ""
echo "Done. NOT touched (flutterfire-managed — regenerate via flutterfire configure):"
echo "  lib/firebase_options.dart, */GoogleService-Info.plist, android/app/google-services.json, firebase.json"
echo ""
echo "Review:  git diff ${FILES[*]}"
echo "Then sanity-check there are no stray references left:"
echo "  grep -rn '${OLD}' lib functions tool .github --include='*.dart' --include='*.js' --include='*.yml'"
