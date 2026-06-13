#!/usr/bin/env bash
# Grant public (allUsers) invoker on every callable function in tulanam.
# Required because Firebase callable functions enforce auth INSIDE the function
# and must be publicly invokable. Run after DRS is relaxed for the project.
set -uo pipefail

FNS=(
  activateLicense bulkUpdateShifts checkAddressGate enrollOperatorFace
  ensureFirebaseAuth fetchMeonAadhaar forcePasswordReset generateLicenseKey
  getFaceFrames getGateStatus initiateMeonDigilocker logGateEvent loginUser
  lookupGstin mfaBeginEnroll mfaConfirmEnroll mfaDisable mfaRegenerateBackupCodes
  mfaStatus migrateFreeTierToTrial migratePinHashes migrateToHierarchy
  notifyBackupResult notifyLicenseActivated notifyMfaChanged notifyPasswordChanged
  registerCredential registerFcmToken registerRfidTag resetOperatorPin
  resetUserPassword sendEmailOTP sendPasswordResetOTP sendPhoneOTP
  sendPinResetChallenge sendReportEmail setOperatorPin storeFaceFrames
  trainOperatorFace triggerGate unregisterFcmToken updateCompanyContact
  updateOperatorEmail validateFaceConsistency validateLicense validateRfidTag
  verifyAddressCode verifyDocument verifyEmailOTP verifyGstinOwnership
  verifyMfaCode verifyOTP verifyOperatorFace verifyOperatorId verifyOperatorPin
  verifyPasswordResetOTP verifyPinResetCode verifyPhoneOTP
)

grant() {
  local fn="$1"
  local out
  # Use the exit code for success — the DRS error text contains the word
  # "allUsers", so a substring match on output gives false positives.
  if out=$(gcloud functions add-invoker-policy-binding "$fn" \
    --region=asia-south1 --project=tulanam --member=allUsers \
    --account=tech@tulanam.com --quiet < /dev/null 2>&1); then
    echo "OK   $fn"
  else
    echo "FAIL $fn :: $(echo "$out" | grep -iE 'error|permitted|denied' | head -1)"
  fi
}
export -f grant

printf '%s\n' "${FNS[@]}" | xargs -P 8 -I {} bash -c 'grant "$@"' _ {}
echo "=== done ==="
