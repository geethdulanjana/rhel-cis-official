#!/bin/bash
# =============================================================
# scripts/05-install-tat-agent.sh — install the TAT agent into the image.
#
# Runs AFTER CIS hardening, BEFORE snapshot, so the resulting hardened image
# ships with the Tencent Automation Tools (TAT) agent. The CIS-hardened sshd
# blocks root SSH, so TAT is how the cis-image-builder validation flow drives a
# booted CVM (reboot + OpenSCAP) without any SSH/login.
#
# Idempotent + non-fatal: a failure here must not fail the whole build (the
# image is still valid, just not TAT-manageable), so it exits 0.
# =============================================================
set -uo pipefail
echo "===== Installing TAT agent (post-hardening) — $(date -u) ====="

if systemctl is-active --quiet tat_agent 2>/dev/null; then
  echo "TAT agent already active."
  exit 0
fi

# /tmp may be noexec after CIS hardening; run the installer from /root.
cd /root || true

if command -v wget >/dev/null 2>&1; then
  wget -qO /root/tat_agent_installer.sh \
    https://mirrors.tencentyun.com/install/tat_agent/tat_agent_installer.sh || true
elif command -v curl >/dev/null 2>&1; then
  curl -fsSL -o /root/tat_agent_installer.sh \
    https://mirrors.tencentyun.com/install/tat_agent/tat_agent_installer.sh || true
fi

if [ -s /root/tat_agent_installer.sh ]; then
  sh /root/tat_agent_installer.sh || echo "WARNING: TAT installer returned non-zero"
  rm -f /root/tat_agent_installer.sh
else
  echo "WARNING: could not download TAT agent installer (no internet?)."
fi

# Make sure the service is enabled so it starts on boot of the hardened image.
systemctl enable tat_agent 2>/dev/null || true

if systemctl is-enabled --quiet tat_agent 2>/dev/null; then
  echo "TAT agent installed and enabled."
else
  echo "WARNING: TAT agent not enabled — validation via TAT may not work."
fi
echo "===== TAT agent step complete ====="
exit 0
