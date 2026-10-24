#!/bin/bash
# =============================================================
# scripts/04-openscap-audit.sh — Independent CIS audit with OpenSCAP
#
# Runs AFTER the ansible-lockdown hardening, BEFORE the image snapshot.
# OpenSCAP + the SCAP Security Guide (SSG) implement the CIS benchmark
# independently of the remediation role, so this is real third-party
# compliance evidence — not self-attestation by the role.
#
# Outputs (left in /var/log/openscap so a Packer file provisioner can pull them):
#   /var/log/openscap/report.html     — human-readable report (for auditors)
#   /var/log/openscap/results.xml      — XCCDF results (machine-parseable score)
#   /var/log/openscap/arf.xml          — ARF (full results archive)
#   /var/log/openscap/score.txt        — just the numeric score (quick parse)
#
# Exit code is forced 0: a non-100% score must NOT fail the build (hardening
# intentionally skips some controls for TKE). The score is captured for review.
# =============================================================
set -uo pipefail

OUT=/var/log/openscap
mkdir -p "$OUT"
LOG="$OUT/audit.log"
exec > >(tee -a "$LOG") 2>&1
echo "===== OpenSCAP CIS audit — $(date -u) ====="

# Ensure the scanner + content are present (installed on the builder image, but
# be defensive on a fresh base image).
if ! command -v oscap >/dev/null 2>&1; then
  echo "Installing openscap-scanner + scap-security-guide..."
  sudo dnf install -y openscap-scanner scap-security-guide || {
    echo "WARNING: could not install OpenSCAP; skipping audit."
    echo "0" > "$OUT/score.txt"; exit 0
  }
fi

# Locate the SSG datastream for the running RHEL major version.
. /etc/os-release
MAJOR="${VERSION_ID%%.*}"
DS=""
for cand in \
  "/usr/share/xml/scap/ssg/content/ssg-rhel${MAJOR}-ds.xml" \
  "/usr/share/xml/scap/ssg/content/ssg-rhel${MAJOR}-ds-1.2.xml"; do
  [ -f "$cand" ] && DS="$cand" && break
done
if [ -z "$DS" ]; then
  echo "WARNING: no SSG datastream found for RHEL ${MAJOR}; skipping audit."
  ls -l /usr/share/xml/scap/ssg/content/ 2>/dev/null || true
  echo "0" > "$OUT/score.txt"; exit 0
fi
echo "Datastream: $DS"

# Pick the CIS profile id. SSG profile ids vary by version; try the common ones.
PROFILE=""
for p in \
  "xccdf_org.ssgproject.content_profile_cis" \
  "xccdf_org.ssgproject.content_profile_cis_server_l1" \
  "xccdf_org.ssgproject.content_profile_cis_workstation_l1"; do
  if oscap info "$DS" 2>/dev/null | grep -q "$p"; then PROFILE="$p"; break; fi
done
# Fallback: first profile containing 'cis'
if [ -z "$PROFILE" ]; then
  PROFILE=$(oscap info "$DS" 2>/dev/null | grep -oE 'xccdf_org\.ssgproject\.content_profile_[A-Za-z0-9_]*cis[A-Za-z0-9_]*' | head -1)
fi
if [ -z "$PROFILE" ]; then
  echo "WARNING: no CIS profile found in datastream; listing profiles:"
  oscap info "$DS" 2>/dev/null | sed -n '/Profiles:/,$p' | head -40
  echo "0" > "$OUT/score.txt"; exit 0
fi
echo "Profile: $PROFILE"

# oscap writes temp files; /tmp may be noexec after hardening, so use /root.
export TMPDIR=/root

echo "Running oscap xccdf eval (this can take a few minutes)..."
oscap xccdf eval \
  --profile "$PROFILE" \
  --results "$OUT/results.xml" \
  --results-arf "$OUT/arf.xml" \
  --report "$OUT/report.html" \
  "$DS" || true   # eval returns non-zero when any rule fails; that's expected

# Extract the overall score from the XCCDF results.
SCORE=$(grep -oE '<score[^>]*>[0-9.]+' "$OUT/results.xml" 2>/dev/null | grep -oE '[0-9.]+$' | head -1)
[ -z "$SCORE" ] && SCORE="0"
echo "$SCORE" > "$OUT/score.txt"

# Pass/fail rule tallies for a quick summary.
PASS=$(grep -c '<result>pass</result>' "$OUT/results.xml" 2>/dev/null || echo 0)
FAIL=$(grep -c '<result>fail</result>' "$OUT/results.xml" 2>/dev/null || echo 0)
echo "===== OpenSCAP audit complete: score=${SCORE}%  pass=${PASS} fail=${FAIL} ====="

# ── Validation integration (TAT-driven runs) ─────────────────────────────────
# When run via TAT on a throwaway validation CVM, the runner can't use a Packer
# file-download. Instead:
#   1. emit machine-parseable markers on STDOUT (TAT captures stdout), and
#   2. optionally upload the HTML report to COS if CIS_VAL_COS_URL is set.
# These markers are harmless during a normal Packer build (just extra log lines).
echo "VAL_SCORE=${SCORE}"
echo "VAL_PASS=${PASS}"
echo "VAL_FAIL=${FAIL}"

if [ -n "${CIS_VAL_COS_URL:-}" ] && [ -f "$OUT/report.html" ]; then
  # CIS_VAL_COS_URL is a full COS object URL for the report, e.g.
  #   https://<bucket>.cos.<region>.myqcloud.com/validations/<id>/report.html
  # coscli/tccli may not be present on a hardened image; prefer tccli if there,
  # else fall back to a signed PUT via curl when CIS_VAL_COS_PUT is provided.
  echo "Uploading OpenSCAP report to COS: ${CIS_VAL_COS_URL}"
  if command -v coscli >/dev/null 2>&1; then
    coscli cp "$OUT/report.html" "${CIS_VAL_COS_URL}" 2>&1 || echo "WARNING: coscli upload failed"
  elif [ -n "${CIS_VAL_COS_PUT:-}" ]; then
    curl -fsS -X PUT -T "$OUT/report.html" "${CIS_VAL_COS_PUT}" 2>&1 \
      && echo "VAL_REPORT_URL=${CIS_VAL_COS_URL}" \
      || echo "WARNING: curl COS upload failed"
  else
    echo "WARNING: no coscli and no CIS_VAL_COS_PUT — report not uploaded"
  fi
  [ -f "$OUT/report.html" ] && command -v coscli >/dev/null 2>&1 && echo "VAL_REPORT_URL=${CIS_VAL_COS_URL}"
fi
echo "VAL_DONE=1"
exit 0
