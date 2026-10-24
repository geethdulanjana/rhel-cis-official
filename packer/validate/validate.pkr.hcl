# ─────────────────────────────────────────────────────────────────────────────
# validate.pkr.hcl — POST-BOOT OpenSCAP verification of a hardened image.
#
# WHY: The main build snapshots the un-rebooted instance, so reboot-dependent
# CIS controls (grub/kernel cmdline, sysctl, mounts, SELinux relabel, module
# blacklists) are configured but not yet ACTIVE. An OpenSCAP scan there
# under-reports. This template boots a throwaway CVM FROM the hardened image,
# REBOOTS it so those controls take effect, then runs OpenSCAP — giving the
# authoritative, reboot-accurate compliance score.
#
# It is driven by -var hardened_image_id=<img-xxxx> (the just-built image).
# The tencentcloud builder always snapshots, so this produces a short-lived
# "-validate" image; the cis-image-builder runner deletes it right after.
#
# USAGE (the runner does this automatically):
#   packer build -var hardened_image_id=img-xxxx packer/validate.pkr.hcl
#   (results land in audit-results/latest-validate/ on the control node)
# ─────────────────────────────────────────────────────────────────────────────

packer {
  required_plugins {
    tencentcloud = {
      version = ">= 1.2.0"
      source  = "github.com/hashicorp/tencentcloud"
    }
  }
}

variable "region" {
  type    = string
  default = "ap-singapore"
}

variable "zone" {
  type    = string
  default = "ap-singapore-1"
}

variable "instance_type" {
  type    = string
  default = "SA5.MEDIUM4"
}

variable "vpc_id" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "security_group_id" {
  type = string
}

variable "hardened_image_id" {
  type        = string
  description = "The just-built hardened image to verify (img-xxxx)"
}

# Governance tags. A CAM policy DENIES resource creation when dialog:CxoName is
# absent, so the transient validation CVM/image MUST carry the mandatory tags.
variable "environment" {
  type    = string
  default = "cis"
}

variable "project" {
  type    = string
  default = "cis-platform"
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

source "tencentcloud-cvm" "verify" {
  secret_id      = var.secret_id
  secret_key     = var.secret_key
  security_token = var.security_token

  region        = var.region
  zone          = var.zone
  instance_type = var.instance_type

  # Boot FROM the hardened image we just built.
  source_image_id = var.hardened_image_id

  vpc_id            = var.vpc_id
  subnet_id         = var.subnet_id
  security_group_id = var.security_group_id

  associate_public_ip_address = false
  ssh_private_ip              = true
  disk_type = "CLOUD_SSD"
  disk_size = 20

  ssh_username = "root"
  ssh_timeout  = "10m"

  # Throwaway validation image (deleted by the runner right after).
  image_name        = "cis-validate-${formatdate("YYYYMMDD-hhmmss", timestamp())}"
  image_description = "Transient CIS post-boot validation image — safe to delete"

  # Mandatory governance tags (dialog:CxoName required by CAM policy) + purpose.
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
    "Purpose"                   = "cis-postboot-validation"
  }
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
    "Purpose"                   = "cis-postboot-validation-DELETE-ME"
  }
}

build {
  sources = ["source.tencentcloud-cvm.verify"]

  # 1. Reboot so reboot-dependent CIS controls become active, then wait.
  provisioner "shell" {
    expect_disconnect = true
    inline = [
      "echo 'Rebooting to activate reboot-dependent CIS controls...'",
      "sudo systemctl reboot || sudo reboot || true"
    ]
  }

  # 2. After reboot, confirm the box is back and healthy. Emit HEALTH markers
  #    the cis-image-builder validation runner parses for the health verdict.
  provisioner "shell" {
    pause_before = "45s"
    inline = [
      "echo 'Back after reboot:'; uname -r; uptime",
      "echo 'ip_forward now:'; cat /proc/sys/net/ipv4/ip_forward 2>/dev/null || true",
      "echo \"HEALTH system_running=$(systemctl is-system-running 2>/dev/null || echo unknown)\"",
      "echo \"HEALTH failed_units=$(systemctl list-units --state=failed --no-legend --plain 2>/dev/null | wc -l)\"",
      "echo \"HEALTH uptime=$(uptime -p 2>/dev/null || uptime)\"",
      "echo '--- failed units (if any) ---'; systemctl --failed --no-pager 2>/dev/null || true"
    ]
  }

  # 3. Run the SAME OpenSCAP audit script — now against the rebooted system.
  #    bash-invoke so a noexec /tmp doesn't block it.
  provisioner "shell" {
    remote_folder   = "/root"
    execute_command = "chmod +x {{ .Path }}; {{ .Vars }} bash '{{ .Path }}'"
    # script path is relative to the packer WORKING DIRECTORY. The runner invokes
    # packer with cwd = pipeline root (/opt/cis-pipeline), so this resolves to
    # /opt/cis-pipeline/scripts/04-openscap-audit.sh.
    script          = "scripts/04-openscap-audit.sh"
  }

  # 4. Pull the post-boot results. `destination` is relative to the packer
  # working directory; the runner invokes packer from the pipeline root, so this
  # lands at <pipeline>/audit-results/latest-validate/.
  provisioner "file" {
    direction   = "download"
    source      = "/var/log/openscap/"
    destination = "audit-results/latest-validate/"
  }
}
