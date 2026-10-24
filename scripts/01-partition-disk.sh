#!/bin/bash
# =============================================================
# scripts/01-partition-disk.sh — Two-Volume LVM Setup (Tencent Cloud)
#
# PURPOSE:
#   Set up LVM on the SECOND CBS volume (/dev/vdb) for CIS
#   Benchmark-required separate partitions. Root volume is
#   left completely untouched.
#
# ARCHITECTURE:
#   Volume 1 (/dev/vda) — Root, untouched by this script
#     /, /boot — stock RHEL 9 layout
#
#   Volume 2 (/dev/vdb) — This script sets up LVM here
#     data_vg/lv_var        → /var           ( 8 GB)
#     data_vg/lv_var_tmp    → /var/tmp       ( 2 GB)
#     data_vg/lv_var_log    → /var/log       ( 8 GB)
#     data_vg/lv_var_audit  → /var/log/audit ( 4 GB)
#     data_vg/lv_home       → /home          ( 4 GB)
#     data_vg/lv_tmp        → /tmp           ( 2 GB)
#     Total: 28 GB — remaining ~2 GB left unallocated
#     in data_vg for future expansion via lvextend.
#
# TENCENT CLOUD DIFFERENCES FROM AWS:
#   - Device naming: /dev/vdb (virtio) instead of /dev/xvdb or NVMe
#   - CBS (Cloud Block Storage) instead of EBS
#   - Image snapshot includes data disk if data_disks block is in Packer
#
# CALLED BY PACKER AS:
#   provisioner "shell" {
#     script = "scripts/01-partition-disk.sh"
#   }
# =============================================================

set -euo pipefail
set -x

# ============================================================
# PART A: Install required tools
# ============================================================
echo "=== PART A: Install LVM tools ==="
dnf install -y lvm2
modprobe dm_mod
echo "LVM tools installed"

# ============================================================
# PART B: Identify the second (CIS data) volume
#
# On Tencent Cloud CVM with virtio drivers:
#   System disk: /dev/vda
#   Data disk:   /dev/vdb
# ============================================================
echo "=== PART B: Identify CIS data volume ==="

ROOT_PART=$(findmnt -n -o SOURCE /)
echo "Root partition: ${ROOT_PART}"

ROOT_DISK_NAME=$(lsblk -no PKNAME "${ROOT_PART}")
ROOT_DISK="/dev/${ROOT_DISK_NAME}"
echo "Root disk: ${ROOT_DISK}"

# Find the blank data disk
DATA_DISK=""
while IFS= read -r disk_name; do
    candidate="/dev/${disk_name}"

    # Skip root disk
    if [ "${candidate}" = "${ROOT_DISK}" ]; then
        continue
    fi

    # Skip loop devices
    if [[ "${disk_name}" == loop* ]]; then
        continue
    fi

    # Skip disks with existing partitions
    PART_COUNT=$(lsblk -n "${candidate}" | grep -c "part" || echo "0")
    if [ "${PART_COUNT}" -gt 0 ]; then
        echo "WARNING: ${candidate} already has partitions — skipping"
        continue
    fi

    # Skip disks with existing filesystem
    if blkid "${candidate}" &>/dev/null; then
        echo "WARNING: ${candidate} already has a filesystem — skipping"
        continue
    fi

    DATA_DISK="${candidate}"
    break
done < <(lsblk -dn -o NAME --sort NAME)

if [ -z "${DATA_DISK}" ]; then
    echo "ERROR: Could not find a blank second CBS volume"
    echo "Expected Packer to attach a data disk (typically /dev/vdb)"
    echo "Current block devices:"
    lsblk
    exit 1
fi

DATA_DISK_SIZE=$(lsblk -dn -o SIZE "${DATA_DISK}" | tr -d ' ')
echo "CIS data volume: ${DATA_DISK} (${DATA_DISK_SIZE})"

# ============================================================
# PART C: Create LVM structure on the data volume
# ============================================================
echo "=== PART C: Create LVM structure ==="

pvcreate "${DATA_DISK}"
echo "PV created on ${DATA_DISK}"

vgcreate data_vg "${DATA_DISK}"
echo "VG data_vg created"

lvcreate -L  8G -n lv_var       data_vg && echo "lv_var created (8 GB → /var)"
lvcreate -L  2G -n lv_var_tmp   data_vg && echo "lv_var_tmp created (2 GB → /var/tmp)"
lvcreate -L  8G -n lv_var_log   data_vg && echo "lv_var_log created (8 GB → /var/log)"
lvcreate -L  4G -n lv_var_audit data_vg && echo "lv_var_audit created (4 GB → /var/log/audit)"
lvcreate -L  4G -n lv_home      data_vg && echo "lv_home created (4 GB → /home)"
lvcreate -L  2G -n lv_tmp       data_vg && echo "lv_tmp created (2 GB → /tmp)"

echo "--- LVM structure ---"
vgdisplay data_vg
lvdisplay data_vg

# ============================================================
# PART D: Format all logical volumes with XFS
# ============================================================
echo "=== PART D: Format logical volumes ==="

mkfs.xfs -f /dev/data_vg/lv_var       && echo "lv_var formatted (XFS)"
mkfs.xfs -f /dev/data_vg/lv_var_tmp   && echo "lv_var_tmp formatted (XFS)"
mkfs.xfs -f /dev/data_vg/lv_var_log   && echo "lv_var_log formatted (XFS)"
mkfs.xfs -f /dev/data_vg/lv_var_audit && echo "lv_var_audit formatted (XFS)"
mkfs.xfs -f /dev/data_vg/lv_home      && echo "lv_home formatted (XFS)"
mkfs.xfs -f /dev/data_vg/lv_tmp       && echo "lv_tmp formatted (XFS)"

# ============================================================
# PART E: Migrate existing data to new LVs
# ============================================================
echo "=== PART E: Migrate existing data to new LVs ==="

# --- Migrate /var ---
echo "Migrating /var..."
mkdir -p /mnt/new_var
mount /dev/data_vg/lv_var /mnt/new_var
rsync -aAX --quiet /var/ /mnt/new_var/
umount /mnt/new_var
rmdir /mnt/new_var
echo "/var migrated"

# --- Migrate /home ---
echo "Migrating /home..."
mkdir -p /mnt/new_home
mount /dev/data_vg/lv_home /mnt/new_home
rsync -aAX --quiet /home/ /mnt/new_home/
umount /mnt/new_home
rmdir /mnt/new_home
echo "/home migrated"

# --- Migrate /tmp ---
echo "Migrating /tmp..."
mkdir -p /mnt/new_tmp
mount /dev/data_vg/lv_tmp /mnt/new_tmp
rsync -aAX --quiet /tmp/ /mnt/new_tmp/ || true
umount /mnt/new_tmp
rmdir /mnt/new_tmp
echo "/tmp migrated"

# --- Migrate /var/log ---
echo "Migrating /var/log..."
mkdir -p /mnt/new_var_log
mount /dev/data_vg/lv_var_log /mnt/new_var_log
rsync -aAX --quiet /var/log/ /mnt/new_var_log/
umount /mnt/new_var_log
rmdir /mnt/new_var_log
echo "/var/log migrated"

# --- Migrate /var/log/audit ---
echo "Migrating /var/log/audit..."
mkdir -p /mnt/new_var_audit
mount /dev/data_vg/lv_var_audit /mnt/new_var_audit
if [ -d /var/log/audit ]; then
    rsync -aAX --quiet /var/log/audit/ /mnt/new_var_audit/
fi
umount /mnt/new_var_audit
rmdir /mnt/new_var_audit
echo "/var/log/audit migrated"

# --- Migrate /var/tmp ---
echo "Migrating /var/tmp..."
mkdir -p /mnt/new_var_tmp
mount /dev/data_vg/lv_var_tmp /mnt/new_var_tmp
rsync -aAX --quiet /var/tmp/ /mnt/new_var_tmp/ || true
umount /mnt/new_var_tmp
rmdir /mnt/new_var_tmp
echo "/var/tmp migrated"

# ============================================================
# PART F: Update /etc/fstab
# ============================================================
echo "=== PART F: Update /etc/fstab ==="

cp /etc/fstab /etc/fstab.bak.$(date +%Y%m%d%H%M%S)

cat >> /etc/fstab << 'EOF'

# -------------------------------------------------------
# CIS Benchmark 1.1.2 — Separate partitions on LVM (Data Disk)
# Added by 01-partition-disk.sh during Packer build
# -------------------------------------------------------
/dev/data_vg/lv_var         /var             xfs   defaults,noatime,nodev,nosuid,nofail,x-systemd.device-timeout=30s                  0 2
/dev/data_vg/lv_var_tmp     /var/tmp         xfs   defaults,noatime,nodev,nosuid,noexec,nofail,x-systemd.device-timeout=30s           0 2
/dev/data_vg/lv_var_log     /var/log         xfs   defaults,noatime,nodev,nosuid,noexec,nofail,x-systemd.device-timeout=30s           0 2
/dev/data_vg/lv_var_audit   /var/log/audit   xfs   defaults,noatime,nodev,nosuid,noexec,nofail,x-systemd.device-timeout=30s           0 2
/dev/data_vg/lv_home        /home            xfs   defaults,noatime,nodev,nosuid,nofail,x-systemd.device-timeout=30s                  0 2
/dev/data_vg/lv_tmp         /tmp             xfs   defaults,noatime,nodev,nosuid,noexec,nofail,x-systemd.device-timeout=30s           0 2
EOF

echo "--- Updated /etc/fstab ---"
cat /etc/fstab

# ============================================================
# PART G: Mount all new LVs at their final locations
# ============================================================
echo "=== PART G: Mount LVs at final locations ==="

mount /dev/data_vg/lv_var /var
echo "/var mounted"

mount /dev/data_vg/lv_var_tmp /var/tmp
echo "/var/tmp mounted"

mount /dev/data_vg/lv_var_log /var/log
echo "/var/log mounted"

mkdir -p /var/log/audit
mount /dev/data_vg/lv_var_audit /var/log/audit
echo "/var/log/audit mounted"

mount /dev/data_vg/lv_home /home
echo "/home mounted"

mount /dev/data_vg/lv_tmp /tmp
echo "/tmp mounted"

# ============================================================
# PART H: Final verification
# ============================================================
echo ""
echo "======================================="
echo " TWO-VOLUME LVM SETUP COMPLETE"
echo "======================================="
echo ""
echo "Block devices:"
lsblk
echo ""
echo "Volume group:"
vgs data_vg
echo ""
echo "Logical volumes:"
lvs data_vg
echo ""
echo "Mount points:"
df -h /var /var/tmp /var/log /var/log/audit /home /tmp
echo ""
echo "fstab:"
cat /etc/fstab
echo ""
echo "======================================="
echo " Root (/) is on Volume 1 — untouched"
echo " CIS partitions on Volume 2 — LVM"
echo ""
echo " After launch, to extend a partition:"
echo "   pvresize /dev/vdb"
echo "   lvextend -L +10G /dev/data_vg/lv_var"
echo "   xfs_growfs /var"
echo "======================================="
