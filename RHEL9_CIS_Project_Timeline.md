# RHEL 9 CIS Hardening — Project Timeline
**Project:** TKE Node CIS Hardening (RHEL 9)
**Target:** ~80% CIS Benchmark v2.0.0 coverage (Level 1 + Level 2)
**Start:** 2026-09-01
**End:** 2026-12-12
**Total Duration:** ~15 weeks

---

## Coverage Target

| Level | Target | Rationale |
|---|---|---|
| L1 Server | 95%+ | Practical baseline, low disruption risk |
| L2 Server | 70%+ | High-value controls only; TKE-incompatible controls excepted |
| Overall | ~80% | Remaining 20% documented in exceptions register |

Controls excluded from scope are not failures — they are formally documented in the **TKE CIS Exceptions Register** (T25) with justification (e.g. SELinux context gaps, container runtime conflicts, TKE bootstrap requirements).

---

## Timeline Overview

```
     Sep        Oct        Nov        Dec
     |--P0-P1---|--P2-P3--|--P4----|--P5--|--P6--|--P7-|
       Infra+FS  Svc+Net   SSH/PAM  Audit  Perm   TKE
       §1 Harden §2§3§4    §5       §6     §7     Val
```

---

## Phase 0 — Infrastructure Setup & Pipeline
**Duration:** 1.5 weeks | **2026-09-01 → 2026-09-11**

### Goal
Get the build pipeline working end-to-end before touching any CIS controls. Nothing else can start without this.

### Tasks
| ID | Task | Owner | Notes |
|---|---|---|---|
| T04 | Packer scaffolding — tencentcloud-cvm builder | Infra | Base template, no hardening yet |
| T05 | RHEL licensing decision / Rocky Linux fallback | PM + Infra | Unblocks T06 |
| T01 | RHEL image sourcing model confirmed | PM | Tencent-licensed vs self-import |
| T02 | Instance family certification check | Infra | SA5/SA2 vs Red Hat certified list |
| T06 | Packer + Ansible Lockdown role wired together | Infra | First successful image build |

### Deliverable
A Packer build that produces a RHEL 9 (or Rocky 9) image with the CIS role installed but **all sections disabled** — pipeline proven, no hardening applied yet.

---

## Phase 1 — Section 1: Initial Setup & Filesystem Hardening
**Duration:** 2 weeks | **2026-09-14 → 2026-09-25**

### CIS Coverage
| Sub-section | Controls | Description | L1/L2 |
|---|---|---|---|
| 1.1.1.x | 9 controls | Disable unused filesystem kernel modules (cramfs, squashfs, udf etc.) | L1 |
| 1.1.2.1.x | 4 controls | `/tmp` — separate partition, nodev/nosuid/noexec | L1 |
| 1.1.2.2.x | 4 controls | `/dev/shm` — nodev/nosuid/noexec | L1 |
| 1.1.2.3.x | 3 controls | `/home` — separate partition, nodev/nosuid | L1 |
| 1.1.2.4.x | 3 controls | `/var` — separate partition, nodev/nosuid | L1 |
| 1.1.2.5.x | 4 controls | `/var/tmp` — nodev/nosuid/noexec | L1 |
| 1.1.2.6.x | 4 controls | `/var/log` — separate partition, nodev/nosuid/noexec | L1 |
| 1.1.2.7.x | 4 controls | `/var/log/audit` — separate partition | L1 |
| 1.2.1.x | 4 controls | Package repo GPG checks | L1 |
| 1.2.2.x | 1 control | Package updates | L1 |
| 1.3.1.x | 8 controls | SELinux — enforcing mode, targeted policy | L1/L2 |
| 1.4.x | 2 controls | Bootloader password | L1 |
| 1.5.x | 4 controls | Process hardening (ASLR, ptrace, core dumps) | L1 |
| 1.6.x | 7 controls | Crypto policy (DEFAULT/FUTURE/FIPS) | L1 |
| 1.7.x | 6 controls | Login warning banners (motd, issue, issue.net) | L1 |
| 1.8.x | 10 controls | GNOME/GDM — **skip** (server, no GUI) | — |

### Key Decisions
- LVM partition layout must be designed **before** Packer build (T08) — partitions cannot be resized post-build
- SELinux enforcing mode is high-risk for TKE (R05) — validate containerd/kubelet contexts before enabling
- Bootloader password (1.4.1) — skip or document exception for cloud images (no console access)
- GNOME (1.8.x) — fully skipped, server image has no GUI

### Deliverable
Packer image with filesystem layout hardened. Pre/post goss audit score baseline established.

---

## Phase 2 — Section 2: Services & Section 3: Network Kernel
**Duration:** 2 weeks | **2026-09-28 → 2026-10-09**

### CIS Coverage — Section 2
| Sub-section | Controls | Description | L1/L2 |
|---|---|---|---|
| 2.1.x | 22 controls | Disable/remove unused server services (avahi, dhcp, dns, ftp, samba, http, etc.) | L1 |
| 2.2.x | 5 controls | Remove unused client packages (ftp, ldap, nis, telnet, tftp) | L1 |
| 2.3.x | 3 controls | Time sync — chrony configured and running | L1 |
| 2.4.x | 9 controls | cron/at — permissions, allow/deny files | L1 |

### CIS Coverage — Section 3
| Sub-section | Controls | Description | L1/L2 |
|---|---|---|---|
| 3.1.x | 3 controls | Disable wireless, bluetooth | L1 |
| 3.2.x | 4 controls | Disable unused network kernel modules (dccp, sctp, rds, tipc) | L1/L2 |
| 3.3.x | 11 controls | Sysctl network parameters (IP forwarding, ICMP, source routing, etc.) | L1 |

### Key Decisions
- `nfs_server` and `rpc_server` — set to `true` (TKE may require NFS for persistent volumes); review per environment
- `rhel9cis_ipv6_required: true` — keep enabled, TKE uses IPv6 internally in some configurations
- Sysctl IP forwarding (`net.ipv4.ip_forward`) — **must stay enabled** for container networking; add to exceptions register

### Deliverable
Image with all unnecessary services removed and network kernel hardened. Exception register draft started (T25).

---

## Phase 3 — Section 4: Firewall
**Duration:** 1 week | **2026-10-12 → 2026-10-16**

### CIS Coverage
| Sub-section | Controls | Description | L1/L2 |
|---|---|---|---|
| 4.1.x | 2 controls | Ensure firewall utility installed | L1 |
| 4.2.x | 2 controls | firewalld default zone, loopback rules | L1 |
| 4.3.x | 4 controls | nftables base chains, tables, default deny | L1 |

### Key Decisions
- Use `firewalld` (default) — aligns with RHEL 9 default and TKE node bootstrap expectations
- Default-deny inbound policy must **not** block kubelet API (10250), CNI, and TKE node-agent ports — add explicit allow rules
- nftables is an alternative but adds complexity; stick with firewalld unless a specific requirement forces nftables

### Deliverable
Firewall configured with default-deny + TKE-required port exceptions documented.

---

## Phase 4 — Section 5: Access, Authentication & Authorization
**Duration:** 3 weeks | **2026-10-19 → 2026-11-06**

### CIS Coverage
| Sub-section | Controls | Description | L1/L2 |
|---|---|---|---|
| 5.1.x | 22 controls | SSH hardening (ciphers, MACs, auth methods, timeouts, access control) | L1 |
| 5.2.x | 7 controls | sudo — pty, logfile, re-auth, timeout, NOPASSWD restrictions | L1 |
| 5.3.1.x | 3 controls | PAM packages (pam_pwquality, pam_faillock) | L1 |
| 5.3.2.x | 5 controls | authselect custom profile | L1 |
| 5.3.3.1.x | 3 controls | pam_faillock — lockout after failed attempts | L1 |
| 5.3.3.2.x | 7 controls | pam_pwquality — complexity, length, history | L1 |
| 5.3.3.3.x | 3 controls | pam_pwhistory — password reuse limit | L1 |
| 5.3.3.4.x | 4 controls | pam_unix — SHA-512 hashing | L1 |
| 5.4.1.x | 6 controls | Shadow password aging (max days, min days, warn age) | L1 |
| 5.4.2.x | 8 controls | Root account, system accounts, nologin shells | L1 |
| 5.4.3.x | 3 controls | User environment (umask, shell timeout, PATH) | L1 |

### Key Decisions
- `rhel9cis_authselect_custom_profile_name` — must be renamed from default `cis_example_profile` before running
- `rhel9cis_sudoers_exclude_nopasswd_list` — add TKE bootstrap user if applicable
- SSH `AllowUsers` — must include the Ansible connecting user or risk lockout
- PAM changes are the **highest risk** section — test thoroughly on a throwaway VM before baking into image

### Deliverable
SSH, sudo, PAM, and password policy hardened. No lockout issues on test VM confirmed.

---

## Phase 5 — Section 6: Logging & Auditing
**Duration:** 2 weeks | **2026-11-09 → 2026-11-20**

### CIS Coverage
| Sub-section | Controls | Description | L1/L2 |
|---|---|---|---|
| 6.1.x | 3 controls | AIDE file integrity — install, init DB, schedule cron | L1 |
| 6.2.1.x | 4 controls | systemd-journald service configuration | L1 |
| 6.2.2.1.x | 4 controls | systemd-journal-remote (forward to central log host) | L2 |
| 6.2.2.x | 4 controls | journald settings (compress, storage, rotation) | L1 |
| 6.2.3.x | 8 controls | rsyslog — **skip** (using journald) | — |
| 6.2.4.1 | 1 control | Log file permissions | L1 |
| 6.3.1.x | 4 controls | auditd service — install, enable, backlog limit | L1 |
| 6.3.2.x | 4 controls | auditd data retention — max size, full/error actions | L1 |
| 6.3.3.x | 21 controls | auditd rules — syscall auditing, privileged commands | L2 |
| 6.3.4.x | 10 controls | auditd file access permissions | L1 |

### Key Decisions
- `rhel9cis_syslog: journald` — skip rsyslog section entirely
- `rhel9cis_journal_upload_url` — set to your central log aggregator IP before baking
- auditd rules (6.3.3.x) are L2 and verbose — high disk I/O impact; tune `max_log_file_size` for TKE node disk layout
- AIDE DB init runs at image build time — subsequent node boots will detect changes from TKE bootstrap (expected); document in exceptions register

### Deliverable
auditd running with CIS rule set. journald forwarding configured. AIDE baseline DB baked into image.

---

## Phase 6 — Section 7: System Maintenance & Exceptions Gate
**Duration:** 1.5 weeks | **2026-11-23 → 2026-12-04**

### CIS Coverage
| Sub-section | Controls | Description | L1/L2 |
|---|---|---|---|
| 7.1.x | 13 controls | System file permissions (/etc/passwd, shadow, group, cron dirs, world-writable) | L1 |
| 7.2.x | 9 controls | Local user/group integrity (duplicate UIDs/GIDs, root UID 0, home dirs) | L1 |

### Key Decisions
- `rhel9cis_suid_sgid_adjust: false` — keep false initially; TKE binaries may require SUID; audit first
- `rhel9cis_no_world_write_adjust: true` — safe to enable
- `rhel9cis_dotperm_ansiblemanaged: false` — leave false; dot file changes can break running sessions
- Run `fs_with_cves.sh` (included in role `files/`) to identify filesystem CVE exposure

### Deliverable
File permission hardening applied. Exceptions register finalized and signed off (T25).

---

## Phase 7 — TKE Integration Validation & OpenSCAP Gate
**Duration:** 1.5 weeks | **2026-11-30 → 2026-12-12**

### Tasks
| ID | Task | Notes |
|---|---|---|
| T26 | OpenSCAP scan as Packer quality gate | `oscap xccdf eval` — fail build if score < 80% |
| T27 | Hardened image boots and joins staging TKE node pool | Validate kubelet, containerd, TKE agent all start |
| T28 | Load/soak test on staging node pool | Run workloads for 48h, check for auditd/SELinux denials |
| T29 | Iterate exceptions register for any bootstrap breakage | Final sign-off |
| T32 | Rolling node pool update automation (cordon/drain/replace) | Automate node refresh with new image |

### Deliverable
Hardened image passing OpenSCAP ≥80% CIS score, successfully joining TKE staging cluster. Exceptions register signed off. Runbook handed over.

---

## Summary Gantt

| Phase | Focus | Start | End | Weeks |
|---|---|---|---|---|
| Phase 0 | Pipeline Setup | Sep 01 | Sep 11 | 1.5 |
| Phase 1 | §1 Filesystem & SELinux | Sep 14 | Sep 25 | 2 |
| Phase 2 | §2 Services + §3 Network | Sep 28 | Oct 09 | 2 |
| Phase 3 | §4 Firewall | Oct 12 | Oct 16 | 1 |
| Phase 4 | §5 SSH / PAM / sudo | Oct 19 | Nov 06 | 3 |
| Phase 5 | §6 Logging & Auditing | Nov 09 | Nov 20 | 2 |
| Phase 6 | §7 File Permissions + Exceptions | Nov 23 | Dec 04 | 1.5 |
| Phase 7 | TKE Validation + OpenSCAP Gate | Nov 30 | Dec 12 | 1.5 |
| **Total** | | **Sep 01** | **Dec 12** | **~15 weeks** |

---

## Risk & Contingency

| Risk | Impact | Mitigation | Contingency Buffer |
|---|---|---|---|
| RHEL licensing delay (R01) | Blocks Phase 0 | Decide Rocky Linux fallback by Aug 22 | 1 week in Phase 0 |
| SELinux breaks TKE join (R05) | Blocks Phase 7 | Test SELinux in Phase 1 on standalone VM | 1 week in Phase 7 |
| PAM lockout during Phase 4 | Blocks image build | Test on throwaway VM before baking | Built into Phase 4 duration |
| auditd disk I/O impact (Phase 5) | Performance risk | Tune log size limits; test under load in Phase 7 | Phase 7 soak test |
| OpenSCAP score < 80% at gate | Delays handover | Track score weekly from Phase 1 onwards | Dec 12 is hard deadline |

---

## Excluded Controls (Exceptions Register Candidates)

The following control categories are expected to be formally excepted rather than implemented:

| Section | Controls | Reason |
|---|---|---|
| 1.4.x | Bootloader password | Cloud image — no physical console access |
| 1.8.x | GNOME/GDM | Server image, no GUI installed |
| 3.3.x | IP forwarding sysctl | Required for container networking (kubelet/CNI) |
| 4.x | Firewall port restrictions | TKE node ports (10250, CNI range) must remain open |
| 6.2.3.x | rsyslog | Using journald instead |
| 6.3.3.x (partial) | auditd syscall rules | Subset may conflict with container syscall patterns |
| 7.1.x (partial) | SUID/SGID removal | TKE/containerd binaries may require SUID |

> All exceptions require written justification and sign-off before Phase 7 completion.

---

*Last updated: 2026-08-13 — start date adjusted to Sep 01, target Dec 12*
*Owner: Infra Team*
*Benchmark: CIS RedHat Enterprise Linux 9 Benchmark v2.0.0*
