#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# Refresh tccli credentials from CAM role metadata
#
# Fetches temporary credentials from the instance metadata service and writes
# them to ~/.tccli/default.credential so Packer and tccli can use them.
#
# NOTE: These credentials expire after a few hours. Run this script before
#       each packer build, or add it to build.sh.
#
# USAGE:
#   /opt/cis-pipeline/scripts/refresh-credentials.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail



# Fetch role name and credentials from instance metadata
ROLE_NAME=$(curl -fsSL http://metadata.tencentyun.com/latest/meta-data/cam/security-credentials/)
CREDS=$(curl -fsSL "http://metadata.tencentyun.com/latest/meta-data/cam/security-credentials/$ROLE_NAME")

SECRET_ID=$(echo "$CREDS" | jq -r '.TmpSecretId')
SECRET_KEY=$(echo "$CREDS" | jq -r '.TmpSecretKey')
TOKEN=$(echo "$CREDS" | jq -r '.Token')
EXPIRY=$(echo "$CREDS" | jq -r '.ExpiredTime')

export TENCENTCLOUD_SECRET_ID="$SECRET_ID"
export TENCENTCLOUD_SECRET_KEY="$SECRET_KEY"
export TENCENTCLOUD_SECURITY_TOKEN="$TOKEN"

echo $TENCENTCLOUD_SECRET_ID
echo $TENCENTCLOUD_SECRET_KEY
echo $TENCENTCLOUD_SECURITY_TOKEN


PACKER_LOG=1 packer build packer/ 2>&1 | tee logs/packer-build-$(date +%Y%m%d-%H%M%S).log

