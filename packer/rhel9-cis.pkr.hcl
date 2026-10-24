# ─────────────────────────────────────────────────────────────────────────────
# Packer Template — RHEL 9 CIS Hardened Image
#
# This template builds a CIS-hardened RHEL 9 image for TKE worker nodes.
#
# HOW IT WORKS:
#   1. Packer launches a temporary CVM from the base RHEL 9 image
#   2. Connects via SSH
#   3. Runs the Ansible playbook (RHEL9-CIS role)
#   4. Snapshots the disk → creates a custom image
#   5. Destroys the temporary CVM
#
# USAGE (on the builder CVM):
#   cd /opt/cis-pipeline/repo/rhel-cis-official
#   packer init packer/
#   packer build packer/
#
# CREDENTIALS:
#   Packer reads from environment variables or the tccli profile.
#   On the builder CVM with CAM role, it auto-fetches from metadata service.
#   Set TENCENTCLOUD_SECRET_ID and TENCENTCLOUD_SECRET_KEY if running elsewhere.
# ─────────────────────────────────────────────────────────────────────────────

packer {
  required_plugins {
    tencentcloud = {
      version = ">= 1.2.0"
      source  = "github.com/hashicorp/tencentcloud"
    }
    ansible = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/ansible"
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# VARIABLES
# ─────────────────────────────────────────────────────────────────────────────

variable "region" {
  type    = string
  default = "ap-singapore"
}


variable "secret_id" {
  type      = string
  default   = env("TENCENTCLOUD_SECRET_ID")
  sensitive = true
}

variable "secret_key" {
  type      = string
  default   = env("TENCENTCLOUD_SECRET_KEY")
  sensitive = true
}

variable "security_token" {
  type      = string
  default   = env("TENCENTCLOUD_SECURITY_TOKEN")
  sensitive = true
}

variable "zone" {
  type    = string
  default = "ap-singapore-1"
}

variable "instance_type" {
  type        = string
  default     = "SA5.MEDIUM4"
  description = "Instance type for the temporary build CVM (2C4G is enough)"
}

variable "source_image_id" {
  type        = string
  description = "Base RHEL 10 image ID from Tencent marketplace"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID where the temporary build CVM will launch"
}

variable "subnet_id" {
  type        = string
  description = "Subnet ID for the temporary build CVM"
}

variable "security_group_id" {
  type        = string
  description = "Security group ID for the temporary build CVM"
}

variable "image_name_prefix" {
  type    = string
  default = "rhel10-cis-hardened"
}

variable "image_description" {
  type    = string
  default = "RHEL 10 CIS Benchmark v2.0.0 hardened image for TKE nodes"
}

variable "environment" {
  type    = string
  default = "cis"
}

variable "project" {
  type    = string
  default = "nprod-tencent"
}

# ─────────────────────────────────────────────────────────────────────────────
# SOURCE — Defines the temporary CVM that Packer will create
# ─────────────────────────────────────────────────────────────────────────────

source "tencentcloud-cvm" "rhel10_cis" {
    # Credentials — read from environment variables
  # Set TENCENTCLOUD_SECRET_ID, TENCENTCLOUD_SECRET_KEY, TENCENTCLOUD_SECURITY_TOKEN
  secret_id      = var.secret_id
  secret_key     = var.secret_key
  security_token = var.security_token

  region        = var.region
  zone          = var.zone
  instance_type = var.instance_type

  # Base image — RHEL 9 from Tencent marketplace
  source_image_id = var.source_image_id

  # Network — launch in same VPC as the builder
  vpc_id            = var.vpc_id
  subnet_id         = var.subnet_id
  security_group_id = var.security_group_id

  # No public IP needed — Packer connects via private IP (ssh_private_ip)
  associate_public_ip_address = false
  ssh_private_ip              = true

  # System disk — 20GB for / and /boot (untouched by LVM)
  disk_type = "CLOUD_SSD"
  disk_size = 20

  # Data disk — 30GB for CIS-required LVM partitions
  # /var, /var/tmp, /var/log, /var/log/audit, /home, /tmp
  data_disks {
    disk_type = "CLOUD_SSD"
    disk_size = 30
  }

  # SSH — Packer generates a temporary keypair
  ssh_username = "root"
  ssh_timeout  = "10m"

  # Output image
  image_name        = "${var.image_name_prefix}-${formatdate("YYYYMMDD-hhmm", timestamp())}"
  image_description = var.image_description

  # Tags on the temporary instance (not the final image)
  run_tags = {
    "dialog:Environment"        = var.environment
    "dialog:Project"            = var.project
    "dialog:Department"         = "IT"
    "dialog:CostCenter"         = "Cloudops"
    "dialog:DataClassification" = "Cloudops"
    "dialog:Owner"              = "Geeth.Dulanjana"
    "dialog:ApplicationName"    = var.project
    "dialog:Budgetcode"         = "Cloudops"
    "dialog:CxoName"            = "IT"
    "ManagedBy"                 = "packer"
    "Purpose"                   = "cis-image-build"
  }

  # Tags on the resulting image
  image_tags = {
    "dialog:Environment"        = var.environment
    "dialog:Project"            = var.project
    "dialog:Department"         = "IT"
    "dialog:CostCenter"         = "Cloudops"
    "dialog:DataClassification" = "Cloudops"
    "dialog:Owner"              = "Geeth.Dulanjana"
    "dialog:ApplicationName"    = var.project
    "dialog:Budgetcode"         = "Cloudops"
    "dialog:CxoName"            = "IT"
    "ManagedBy"                 = "packer"
    "CIS-Benchmark"             = "RHEL9-v2.0.0"
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# BUILD — What to do on the temporary CVM before snapshotting
# ─────────────────────────────────────────────────────────────────────────────

build {
  sources = ["source.tencentcloud-cvm.rhel10_cis"]

  # Step 1: Wait for cloud-init to finish
  provisioner "shell" {
    inline = [
      "echo 'Waiting for cloud-init to complete...'",
      "cloud-init status --wait || true",
      "echo 'Cloud-init done.'"
    ]
  }

  # Step 2: Set up LVM partitions on the data disk
  # Creates /var, /var/tmp, /var/log, /var/log/audit, /home, /tmp
  # on the second disk using LVM (CIS 1.1.2.x requirements)
  provisioner "shell" {
    script = "scripts/01-partition-disk.sh"
  }

  # Step 2: Ensure a Python 3 interpreter exists for Ansible on the TARGET.
  # The TARGET only needs *a* python3 to run modules — it does NOT need 3.12
  # (that requirement is for the ansible control node). RHEL 9.5 ships python3
  # (3.9) which is fine. We just make sure /usr/bin/python3 is present; if the
  # image lacks it and has working repos, install it. We do NOT depend on 3.12.
  provisioner "shell" {
    inline = [
      "echo 'Checking for a python3 interpreter on the target...'",
      "command -v python3 || sudo dnf install -y python3 || true",
      "command -v python3 && python3 --version || echo 'WARNING: no python3 found'"
    ]
  }

  # Step 3: Run the CIS hardening playbook
  provisioner "ansible" {
    playbook_file = "ansible/playbook.yml"
    extra_arguments = [
      "--extra-vars", "@ansible/group_vars/all.yml",
      # Let Ansible auto-discover the target interpreter instead of hardcoding a
      # path. 'auto_silent' picks the platform python3 (RHEL 9 = /usr/bin/python3
      # = 3.9; RHEL 10 = 3.12) without the discovery warning. This fixes the
      # "/usr/bin/python3.12: No such file" failure on images without 3.12.
      "--extra-vars", "ansible_python_interpreter=auto_silent",
      "--scp-extra-args", "'-O'"
    ]
    ansible_env_vars = [
      "ANSIBLE_HOST_KEY_CHECKING=False",
      "ANSIBLE_SCP_IF_SSH=True",
      "ANSIBLE_SSH_TRANSFER_METHOD=smart"
    ]
  }

  # Step 3b: Install the TAT agent INTO the hardened image (documented exception
  # to pure CIS). This lets the cis-image-builder validation flow drive a booted
  # CVM via Tencent Automation Tools — the CIS-hardened sshd blocks root SSH, so
  # TAT (no SSH, no login) is the reliable post-boot management path. Runs after
  # hardening so it is captured in the snapshot.
  provisioner "shell" {
    remote_folder   = "/root"
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} bash '{{ .Path }}'"
    script          = "scripts/05-install-tat-agent.sh"
  }

  # Step 4: Independent CIS audit with OpenSCAP (after hardening).
  # Runs via bash so a noexec /tmp (from CIS mount hardening) doesn't block it.
  // provisioner "shell" {
  //   remote_folder   = "/root"
  //   execute_command = "chmod +x {{ .Path }}; {{ .Vars }} bash '{{ .Path }}'"
  //   script          = "scripts/04-openscap-audit.sh"
  // }

  # Step 4b: Pull the OpenSCAP results back to the builder (control node) into a
  # fixed staging dir. The cis-image-builder runner moves this to
  # audit-results/<build_id>/ right after packer exits (one build at a time, so
  # 'latest' is unambiguous). Path is relative to the packer working dir.
  // provisioner "file" {
  //   direction   = "download"
  //   source      = "/var/log/openscap/"
  //   destination = "audit-results/latest/"
  // }



  # Step 5: Clean up before snapshot
  #
  # CIS 1.1.2.x hardening mounts /tmp and /var/tmp with noexec. Packer's default
  # behavior uploads its script to /tmp and executes it directly, which the
  # kernel blocks on a noexec mount ("Permission denied"). Two mitigations:
  #   1. remote_folder=/root  -> stage the script in root's home (not noexec)
  #   2. execute_command runs the script THROUGH bash (interpreter reads the
  #      file as input; the file itself is not exec'd, so noexec doesn't apply)
  provisioner "shell" {
    remote_folder   = "/root"
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} bash '{{ .Path }}'"
    inline = [
      "echo 'Cleaning up before image snapshot...'",

      # Fix cloud-init urllib3 issue FIRST — this must persist into the snapshot
      "pip3 install --force-reinstall 'urllib3<2' requests 2>/dev/null || true",

      # Verify cloud-init works after the fix
      "cloud-init --version && echo 'cloud-init OK' || echo 'cloud-init STILL BROKEN'",

      # Ensure SSH is configured to accept key-based auth
      "sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config",
      "sed -i 's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config",

      # Ensure sshd will start on boot
      "systemctl enable sshd",

      # Remove temporary files
      "rm -rf /tmp/* /var/tmp/*",

      # Clear machine-id (regenerated on boot)
      "truncate -s 0 /etc/machine-id",

      # Clear cloud-init state so it runs fresh on new instances
      "cloud-init clean --logs",

      # Clear bash history
      "history -c",
      "echo 'Cleanup done. Ready for snapshot.'"
    ]
  }
}