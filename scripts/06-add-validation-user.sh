#!/bin/bash
# =============================================================
# scripts/06-add-validation-user.sh — bake the 'cisval' validation user.
#
# Creates a key-only, non-root sudo user used by the cis-image-builder post-boot
# validation flow. On a CIS-hardened image root SSH is disabled, so validation
# needs a standing, key-authenticated account to connect, reboot, and run
# OpenSCAP. The public key is passed in via $VALIDATION_PUBKEY (from the
# Terraform SSM keypair). If empty, this is a no-op.
#
# Security posture:
#   - NO password (locked). Key auth only.
#   - passwordless sudo (NOPASSWD) so validation can reboot + run oscap.
#   - CIS keeps PasswordAuthentication off globally; key auth for a normal user
#     is permitted, so we just ensure this user is allowed to log in.
#
# Non-fatal: exits 0 so a hiccup here never fails the whole build.
# =============================================================
set -uo pipefail
echo "===== Adding validation user 'cisval' — $(date -u) ====="

PUBKEY="${VALIDATION_PUBKEY:-}"
if [ -z "$PUBKEY" ]; then
  echo "VALIDATION_PUBKEY empty — skipping validation user creation."
  exit 0
fi

USER_NAME="cisval"

# Create the user if absent, with a home and bash shell.
if ! id "$USER_NAME" >/dev/null 2>&1; then
  sudo useradd -m -s /bin/bash "$USER_NAME" || { echo "WARNING: useradd failed"; exit 0; }
fi

# Lock the password (key-only login; no password auth).
sudo passwd -l "$USER_NAME" >/dev/null 2>&1 || true

# Install the authorized key.
sudo install -d -m 0700 -o "$USER_NAME" -g "$USER_NAME" "/home/$USER_NAME/.ssh"
echo "$PUBKEY" | sudo tee "/home/$USER_NAME/.ssh/authorized_keys" >/dev/null
sudo chmod 0600 "/home/$USER_NAME/.ssh/authorized_keys"
sudo chown "$USER_NAME:$USER_NAME" "/home/$USER_NAME/.ssh/authorized_keys"

# Passwordless sudo for the validation tasks (reboot + oscap).
echo "$USER_NAME ALL=(ALL) NOPASSWD:ALL" | sudo tee "/etc/sudoers.d/90-$USER_NAME" >/dev/null
sudo chmod 0440 "/etc/sudoers.d/90-$USER_NAME"

# CIS hardening may restrict logins via AllowUsers/AllowGroups in sshd_config.
# If an allow-list is present, make sure cisval is included so it can log in.
SSHD=/etc/ssh/sshd_config
if sudo grep -qiE '^\s*AllowUsers' "$SSHD" 2>/dev/null; then
  if ! sudo grep -qiE "^\s*AllowUsers.*\b$USER_NAME\b" "$SSHD"; then
    echo "appending $USER_NAME to existing AllowUsers"
    sudo sed -i -E "s/^(\s*AllowUsers.*)$/\1 $USER_NAME/I" "$SSHD"
  fi
fi
if sudo grep -qiE '^\s*AllowGroups' "$SSHD" 2>/dev/null; then
  # Add cisval to the first allowed group so AllowGroups doesn't block it.
  GRP=$(sudo grep -iE '^\s*AllowGroups' "$SSHD" | head -1 | awk '{print $2}')
  if [ -n "$GRP" ]; then
    echo "adding $USER_NAME to allowed group $GRP"
    sudo groupadd -f "$GRP" 2>/dev/null || true
    sudo usermod -aG "$GRP" "$USER_NAME" 2>/dev/null || true
  fi
fi

echo "validation user '$USER_NAME' ready (key-only, NOPASSWD sudo)."
echo "===== validation user step complete ====="
exit 0
