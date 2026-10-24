# TKE RHEL 9 CIS Hardening — Task Tracker

**Project:** TKE Node CIS Hardening (RHEL 9)
**Benchmark:** CIS RedHat Enterprise Linux 9 v2.0.0
**Target:** ~80% CIS compliance (L1 95%+, L2 70%+)
**Last Updated:** 2026-08-21

---

## Overall Progress

| Phase | Focus | Status | Image ID | Date |
|-------|-------|--------|----------|------|
| Phase 0 | Pipeline Setup | ✅ Complete | img-r1jkwbt8 | 2026-08-19 |
| Phase 1 | §1 Filesystem & Initial Setup | ✅ Complete (96.6% pass) | img-bxegl2rs (v2 w/LVM) | 2026-08-20 |
| Phase 2 | §2 Services + §3 Network | ⬜ Not Started | — | — |
| Phase 3 | §4 Firewall | ⬜ Not Started | — | — |
| Phase 4 | §5 SSH/PAM/sudo | ⬜ Not Started | — | — |
| Phase 5 | §6 Logging & Auditing | ⬜ Not Started | — | — |
| Phase 6 | §7 File Permissions | ⬜ Not Started | — | — |
| Phase 7 | TKE Validation + OpenSCAP | ⬜ Not Started | — | — |

---

## Phase 0 — Infrastructure & Pipeline Setup

| ID | Task | Status | Notes |
|----|------|--------|-------|
| T01 | RHEL image sourcing confirmed | ✅ Done | Tencent marketplace license, RHEL 9.8 |
| T02 | Instance family selection | ✅ Done | SA5.MEDIUM4 (2C4G) |
| T03 | COS state bucket (bootstrap) | ✅ Done | tf-state-nprod-1452370164 |
| T04 | Packer template created | ✅ Done | packer/rhel9-cis.pkr.hcl |
| T05 | Build CVM provisioned (Terraform) | ✅ Done | envs/cis-pipeline/ |
| T06 | Builder toolchain installed | ✅ Done | Packer 1.16, Ansible 2.16, OpenSCAP, Goss |
| T07 | Ansible role wired to Packer | ✅ Done | ansible/playbook.yml + group_vars/all.yml |
| T08 | First image built (all sections OFF) | ✅ Done | img-r1jkwbt8 (ok=43, changed=3, skipped=669) |

### Issues Resolved During Phase 0

| Issue | Root Cause | Resolution |
|-------|-----------|------------|
| cloud-init user_data not executing | urllib3/requests version conflict broke cloud-init on RHEL 9 | Manual tool install; added fix to bootstrap script |
| dnf update scriptlet failures | systemd/D-Bus not ready during cloud-init | Removed dnf update from bootstrap; run manually post-boot |
| Ansible version incompatible | ansible-core 2.16 requires Python 3.10+ | Installed Python 3.12 from AppStream alongside system Python 3.9 |
| Packer STS credentials not working | Plugin doesn't auto-discover CAM role metadata | Using permanent API keys via env vars for now |
| Packer disk_type invalid | SA5 instances don't support CLOUD_BSSD or CLOUD_PREMIUM | Removed disk_type/disk_size; use source image defaults |
| Ansible SCP transfer failed | RHEL 9 OpenSSH deprecated old SCP; sftp-server at wrong path | Set ANSIBLE_SCP_IF_SSH=True + --scp-extra-args '-O' |

### Issues Resolved During Phase 1

| Issue | Root Cause | Resolution |
|-------|-----------|------------|
| 38 fstab/partition audit failures | Cloud image single root partition | Added 30GB data disk with LVM (6 separate partitions) |
| CRLF in role scripts (fs_with_cves.sh) | Repo cloned from Windows | `find ... -exec sed -i 's/\r$//' {} \;` on builder |
| Packer `$HOME` not set during cloud-init | cloud-init doesn't set HOME | Added `export HOME=/root` to bootstrap script |
| Hardened image SSH/TAT not working | Missing data disk → LVM mounts fail → /var broken | Added data_disk_snapshot_id to Terraform CVM module |
| cloud-init still broken on hardened image | urllib3 v2 removed packages.six | Pin `urllib3<2` in Packer cleanup step |
| Goss audit CRLF errors | Audit repo cloned with Windows line endings | `sed -i 's/\r$//'` on .sh and .yml files |

---

## Phase 1 — Section 1: Initial Setup & Filesystem Hardening

**Build Result:** ok=130, changed=44, skipped=590
**Image:** img-bxegl2rs
**Validation:** 🔄 In Progress

### Controls Applied

| Sub-section | Controls | Description | Status | Notes |
|-------------|----------|-------------|--------|-------|
| 1.1.1.x | 9 | Disable unused filesystem kernel modules | ✅ Passed | cramfs, freevxfs, hfs, hfsplus, jffs2, squashfs, udf, usb-storage |
| 1.1.2.1.x | 4 | /tmp mount options (nodev, nosuid, noexec) | ✅ Passed | LVM partition on data disk |
| 1.1.2.2.x | 4 | /dev/shm mount options | ✅ Passed | nodev, nosuid, noexec |
| 1.1.2.3.x | 3 | /home mount options | ✅ Passed | LVM partition on data disk |
| 1.1.2.4.x | 3 | /var mount options | ✅ Passed | LVM partition on data disk |
| 1.1.2.5.x | 4 | /var/tmp mount options | ✅ Passed | LVM partition on data disk |
| 1.1.2.6.x | 4 | /var/log mount options | ✅ Passed | LVM partition on data disk |
| 1.1.2.7.x | 4 | /var/log/audit mount options | ✅ Passed | LVM partition on data disk |
| 1.2.1.x | 3/4 | Package repo GPG checks | ✅ Passed | 1.2.1.3 (repo_gpgcheck) SKIPPED — Tencent repos |
| 1.2.2.x | 0/1 | Package updates | ⏭️ Skipped | 1.2.2.1 disabled — update handled separately |
| 1.3.1.x | 6/8 | SELinux configuration | ⚠️ 4 failures | SELinux permissive (by design) — enforcing deferred to Phase 7 |
| 1.4.x | 0/2 | Bootloader password | ⏭️ Skipped | Cloud image — no console access (exception) |
| 1.5.x | 3/4 | Process hardening (ASLR, ptrace, core dumps) | ⚠️ 1 false positive | ptrace_scope=2 (stricter than required 1) |
| 1.6.x | 7 | Crypto policy (DEFAULT, no SHA1/CBC) | ✅ Passed | Modern crypto enforced system-wide |
| 1.7.x | 5/6 | Login warning banners | ⚠️ 1 minor | /etc/issue banner text mismatch (formatting) |
| 1.8.x | 0/10 | GNOME/GDM | ⏭️ Skipped | Server image — no GUI (exception) |

### Exceptions Register (Section 1)

| Control | Description | Reason | Exception Type |
|---------|-------------|--------|---------------|
| 1.2.1.3 | repo_gpgcheck enabled | Tencent marketplace repos don't sign metadata | Permanent |
| 1.2.2.1 | dnf update during build | Handled separately; causes scriptlet failures in Packer | Process |
| 1.3.1.5 | SELinux enforcing mode | Set to permissive until TKE validation in Phase 7 | Temporary |
| 1.4.x | Bootloader password | Cloud image — no physical console access | Permanent |
| 1.8.x | GNOME/GDM hardening | Server image with no GUI installed | Permanent |

### Validation Checklist

| Check | Method | Status | Result |
|-------|--------|--------|--------|
| Kernel modules blacklisted | Goss audit | ✅ Passed | All 8 modules blacklisted + install /bin/true |
| LVM partitions mounted | Goss audit | ✅ Passed | /var, /tmp, /home, /var/log, /var/log/audit, /var/tmp |
| Mount options (nodev/nosuid/noexec) | Goss audit | ✅ Passed | All fstab entries correct |
| /dev/shm mount options | Goss audit | ✅ Passed | nodev, nosuid, noexec |
| SELinux permissive | Goss audit | ✅ Expected fail | 4 failures (enforcing deferred) |
| ASLR enabled | Goss audit | ✅ Passed | kernel.randomize_va_space=2 |
| ptrace restricted | Goss audit | ⚠️ False positive | ptrace_scope=2 (stricter than audit's expected 1) |
| Core dumps disabled | Goss audit | ✅ Passed | ProcessSizeMax=0 |
| Crypto policy | Goss audit | ✅ Passed | Not LEGACY |
| GPG checks | Goss audit | ✅ Passed | gpgcheck=1 globally |
| Banners set | Goss audit | ⚠️ Minor fail | /etc/issue text format mismatch |
| Goss audit (Section 1) | `run_audit.sh` | ✅ Done | **Count: 177, Failed: 6, Skipped: 0 (96.6% pass)** |

### Goss Audit Results — Final (2026-08-20)

| Metric | v1 (pre-LVM) | v2 (with LVM) | Improvement |
|--------|-------------|---------------|-------------|
| Total tests | 177 | 177 | — |
| Passed | 119 | **171** | +52 |
| Failed | 42 | **6** | -36 |
| Skipped | 16 | 0 | -16 |
| Pass rate | 74% | **96.6%** | +22.6% |

**6 remaining failures (all documented):**

| # | Control | Failure | Classification |
|---|---------|---------|---------------|
| 1-2 | 1.3.1.5 | SELinux not enforcing (config + runtime) | Temporary exception |
| 3-4 | 1.3.1.6 | Unconfined services running | Temporary exception (permissive mode) |
| 5 | 1.7.x | /etc/issue banner text format mismatch | Minor — fixable |
| 6 | 1.5.2 | ptrace_scope=2 (audit expects 1) | False positive (2 is stricter) |

---

### Phase 1b — LVM Partition Implementation (Complete)

| ID | Task | Status | Notes |
|----|------|--------|-------|
| T09 | Packer data_disks block added | ✅ Done | 30GB CLOUD_SSD attached as /dev/vdb |
| T10 | Partition script created (scripts/01-partition-disk.sh) | ✅ Done | Adapted from AWS script for Tencent Cloud |
| T11 | Packer provisioner step added | ✅ Done | Runs before Ansible |
| T12 | Rebuild image with LVM | ✅ Done | 20GB system + 30GB LVM data |
| T13 | Re-run Goss audit on new image | ✅ Done | 6 failures (down from 42) |
| T14 | Verify image boots with LVM mounts active | ✅ Done | All 6 LVs mount on boot |
| T15 | Terraform data_disk_snapshot_id for hardened instances | ✅ Done | CVM module updated with snapshot support |

**Disk Layout (final):**

```
System disk (vda): 20 GB
  / and /boot — stock RHEL 9

Data disk (vdb): 30 GB — LVM (data_vg)
  lv_var         8 GB  → /var           (nodev, nosuid)
  lv_var_tmp     2 GB  → /var/tmp       (nodev, nosuid, noexec)
  lv_var_log     8 GB  → /var/log       (nodev, nosuid, noexec)
  lv_var_audit   4 GB  → /var/log/audit (nodev, nosuid, noexec)
  lv_home        4 GB  → /home          (nodev, nosuid)
  lv_tmp         2 GB  → /tmp           (nodev, nosuid, noexec)
  Unallocated    ~2 GB → future expansion
```

---

## Phase 2 — Section 2: Services + Section 3: Network (Not Started)

| Sub-section | Controls | Description | TKE Notes |
|-------------|----------|-------------|-----------|
| 2.1.x | 22 | Remove unused server services | Low risk |
| 2.2.x | 5 | Remove unused client packages | Low risk |
| 2.3.x | 3 | Time sync (chrony) | Safe |
| 2.4.x | 9 | cron/at permissions | Safe |
| 3.1.x | 3 | Disable wireless/bluetooth | Safe (cloud) |
| 3.2.x | 4 | Disable unused network modules (dccp, sctp) | Safe |
| 3.3.x | 11 | Sysctl network params | ⚠️ ip_forward must stay ON for TKE |

---

## Phase 3 — Section 4: Firewall (Not Started)

| Sub-section | Controls | Description | TKE Notes |
|-------------|----------|-------------|-----------|
| 4.1.x | 2 | Firewall utility installed | firewalld |
| 4.2.x | 2 | Default zone, loopback | Must allow kubelet ports |
| 4.3.x | 4 | nftables default deny | Must whitelist 10250, CNI range |

---

## Phase 4 — Section 5: Access/Auth (Not Started)

| Sub-section | Controls | Description | TKE Notes |
|-------------|----------|-------------|-----------|
| 5.1.x | 22 | SSH hardening | Safe, test ciphers |
| 5.2.x | 7 | sudo configuration | Check TKE bootstrap user |
| 5.3.x | 22 | PAM (faillock, pwquality, pwhistory) | ⚠️ High risk — test thoroughly |
| 5.4.x | 17 | Password/account policies | Safe |

---

## Phase 5 — Section 6: Logging (Not Started)

| Sub-section | Controls | Description | TKE Notes |
|-------------|----------|-------------|-----------|
| 6.1.x | 3 | AIDE file integrity | Init DB during build |
| 6.2.x | 16 | journald configuration | Using journald, skip rsyslog |
| 6.3.x | 39 | auditd rules and config | ⚠️ Disk I/O impact — tune limits |

---

## Phase 6 — Section 7: File Permissions (Not Started)

| Sub-section | Controls | Description | TKE Notes |
|-------------|----------|-------------|-----------|
| 7.1.x | 13 | System file permissions | ⚠️ SUID/SGID — audit first |
| 7.2.x | 9 | User/group integrity | Safe |

---

## Phase 7 — TKE Integration & Final Validation (Not Started)

| ID | Task | Status | Notes |
|----|------|--------|-------|
| T26 | OpenSCAP scan as quality gate | ⬜ | Target ≥80% score |
| T27 | Hardened image joins TKE staging | ⬜ | kubelet, containerd, TKE agent start |
| T28 | 48h soak test | ⬜ | Check auditd/SELinux denials |
| T29 | Exceptions register sign-off | ⬜ | All exceptions documented |
| T30 | Switch SELinux to enforcing | ⬜ | After TKE validation passes |
| T31 | Final image build | ⬜ | All sections enabled + exceptions |
| T32 | Rolling node pool update automation | ⬜ | cordon/drain/replace |

---

## Infrastructure Deployed

| Resource | ID/Name | Location |
|----------|---------|----------|
| VPC | nprod-tencent-cis-vpc | ap-singapore |
| Subnet | nprod-tencent-cis-subnet-builder-1a | 10.10.0.0/26 |
| NAT Gateway | nprod-tencent-cis-nat-1a | For internet egress |
| Security Group | nprod-tencent-cis-sg-builder | SSH from VPC, all outbound |
| Builder CVM | nprod-tencent-cis-packer-builder-1a | SA5.MEDIUM4, RHEL 9.8 |
| CAM Role | nprod-tencent-cis-role-builder | CVM image creation perms |
| State Bucket | tf-state-nprod-1452370164 (prefix: cis-pipeline) | COS, ap-singapore |

---

## Key Decisions Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-08-19 | Use RHEL 9 Tencent licensed image | Avoids BYOL complexity |
| 2026-08-19 | Pipeline runs on dedicated CVM (not local) | All tools installed there |
| 2026-08-19 | Python 3.12 for Ansible (alongside system 3.9) | ansible-core 2.16 requires 3.10+ |
| 2026-08-19 | SELinux permissive initially | Validate TKE compatibility first |
| 2026-08-19 | Skip bootloader password (1.4.x) | Cloud image — no console |
| 2026-08-19 | Skip GNOME (1.8.x) | Server image — no GUI |
| 2026-08-19 | Skip repo_gpgcheck (1.2.1.3) | Tencent repos don't support it |
| 2026-08-19 | Skip dnf update in builds (1.2.2.1) | Scriptlet failures; patch separately |
| 2026-08-19 | Permanent API keys for Packer | STS token not supported by plugin v1.2.0 |
| 2026-08-20 | Two-disk layout (20GB system + 30GB LVM) | CIS requires separate partitions; LVM on data disk matches AWS approach |
| 2026-08-20 | LVM partition sizes: var=8, log=8, audit=4, home=4, tmp=2, var_tmp=2 | Fits 28GB used + 2GB headroom in 30GB disk |
| 2026-08-20 | Remove partition exception from register | No longer needed — LVM implementation resolves fstab failures |
| 2026-08-20 | Pin urllib3<2 in hardened image | v2 removed packages.six which breaks cloud-init |
| 2026-08-20 | Use data_disk_snapshot_id in Terraform | Image includes data disk snapshot; Terraform must reference it |
| 2026-08-20 | Section 1 validated at 96.6% — proceed to Section 2 | 6 remaining failures are documented exceptions or false positives |

---

*Maintained by: Geeth Dulanjana | Infra Team*
*Benchmark: CIS RedHat Enterprise Linux 9 Benchmark v2.0.0*
