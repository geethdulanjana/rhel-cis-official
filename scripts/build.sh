#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# CIS Image Build Script
#
# Fetches credentials, runs packer build, and saves logs.
#
# USAGE:
#   /opt/cis-pipeline/scripts/build.sh
#
# LOGS:
#   /opt/cis-pipeline/logs/packer-build-YYYYMMDD-HHMMSS.log
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

BUILD_DIR="/opt/cis-pipeline"
LOG_DIR="${BUILD_DIR}/logs"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="${LOG_DIR}/packer-build-${TIMESTAMP}.log"

mkdir -p "${LOG_DIR}"

echo "=== CIS Image Build — ${TIMESTAMP} ==="
echo "Log file: ${LOG_FILE}"

# ── Fetch credentials from CAM role ───────────────────────────────────────────
ROLE_NAME=$(curl -fsSL http://metadata.tencentyun.com/latest/meta-data/cam/security-credentials/)
CREDS=$(curl -fsSL "http://metadata.tencentyun.com/latest/meta-data/cam/security-credentials/$ROLE_NAME")

export TENCENTCLOUD_SECRET_ID=$(echo "$CREDS" | jq -r '.TmpSecretId')
export TENCENTCLOUD_SECRET_KEY=$(echo "$CREDS" | jq -r '.TmpSecretKey')
export TENCENTCLOUD_SECURITY_TOKEN=$(echo "$CREDS" | jq -r '.Token')

echo "Credentials fetched for role: $ROLE_NAME"

# ── Run Packer build with full logging ────────────────────────────────────────
cd "${BUILD_DIR}"

# PACKER_LOG=1 enables detailed debug logging
export PACKER_LOG=1
export PACKER_LOG_PATH="${LOG_FILE}"

echo "Starting packer build..."
echo "─────────────────────────────────────────"

packer build packer/ 2>&1 | tee -a "${LOG_FILE}"
BUILD_EXIT=$?

echo "─────────────────────────────────────────"

if [ $BUILD_EXIT -eq 0 ]; then
  echo "✅ Build succeeded — $(date)"
  echo "   Log: ${LOG_FILE}"
  # Extract image ID from log
  IMAGE_ID=$(grep -oP 'img-[a-z0-9]+' "${LOG_FILE}" | tail -1)
  echo "   Image: ${IMAGE_ID}"
else
  echo "❌ Build failed (exit code: ${BUILD_EXIT}) — $(date)"
  echo "   Check log: ${LOG_FILE}"
  exit $BUILD_EXIT
fi
