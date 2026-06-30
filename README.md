# gentoo-template

A scripted, opinionated Gentoo server installer built on top of [oddlama/gentoo-install](https://github.com/oddlama/gentoo-install).

This repository acts as a configuration layer and launcher — it holds a pre-configured `gentoo.conf` (based on the [upstream example](https://github.com/oddlama/gentoo-install/blob/main/gentoo.conf.example)) plus supporting scripts that wire everything together so a full Gentoo server can be installed from the minimal CD with a single command.

---

## Quick start

Boot the target machine from the [Gentoo minimal installation CD](https://www.gentoo.org/downloads/), then run:

```bash
cd /tmp ; git clone https://github.com/saitix/gentoo-template.git ; cd gentoo-template ; ./run.sh
```

`run.sh` clones `oddlama/gentoo-install` into `/tmp`, overlays the local `gentoo.conf`, applies any required workarounds, and launches the upstream installer.

---

## What gets installed

The template targets an **amd64 systemd** server profile and installs:

The full package set lives in the `ADDITIONAL_PACKAGES` array in `gentoo.conf`.

| Category | Packages |
|---|---|
| **Init system** | systemd (`KERNEL_TYPE=bin`, pre-built binary kernel) |
| **Filesystem / storage** | btrfs-progs, parted, lsof, dosfstools, xfsprogs, io-scheduler-udev-rules |
| **Networking** | iproute2, net-tools, ethtool, iptables, openssh, curl, wget, rsync, bind-tools, dnsmasq, iperf, tcpdump, whois, mosh |
| **Security / crypto / auth** | sudo, openssl, cyrus-sasl, libpwquality, certbot, fail2ban |
| **Mail system** | postfix, opendkim, spamassassin, razor, pyzor |
| **Databases** | sqlite, mariadb |
| **Languages / dev** | perl, App-cpanminus, python, pip, nodejs, git |
| **Monitoring / admin** | htop, monit, virt-what, qemu-guest-agent |
| **Terminal / misc tools** | screen, tmux, mc, jq, expect, dialog, cpuid2cpuflags |
| **Overlay (::guru)** | lsyncd, multitail, crudini, nmon, App-perlbrew — _provided by the GURU overlay, which is enabled automatically (see below)_ |
| **Portage** | Git sync against `anongit.gentoo.org`, mirrors via `leaseweb`, `ACCEPT_LICENSE="*"`, `-march=native -O2 -pipe`, `-j8 -l9` |

> **GURU overlay:** Some packages above are not in the main `::gentoo` tree. The `after_configure_portage()` hook in `gentoo.conf` automatically installs `app-eselect/eselect-repository`, enables the GURU overlay (`eselect repository enable guru`), and syncs it (`emaint sync -r guru`) — this happens after the main Portage tree is synced but before `ADDITIONAL_PACKAGES` are emerged, so those packages resolve correctly.

---

## Repository layout

```
gentoo-template/
├── gentoo.conf              # Main installer configuration (edit before running)
├── run.sh                   # Entry point — clones upstream and launches install
├── reformat_partitions.sh   # Helper: wipe & reformat all partitions on all disks
│                            #   (preserves FS type, FS label, GPT partition label)
│                            #   Options: --dry-run, --force
└── debian-gentoo-conv/      # Reference material for porting Debian setups to Gentoo
    ├── debian_only_commands.txt       # Commands that exist only on Debian
    ├── dedicated_scripts_commands.txt # Commands used by the stx scripts
    └── gentoo_packages.txt            # Gentoo packages that satisfy those commands
```

---

## Configuration

All customisation lives in `gentoo.conf`. Key sections:

### Disk layout
```bash
function disk_configuration() {
    create_classic_single_disk_layout swap='2GiB' type='efi' luks='false' \
        root_fs='ext4' '/dev/disk/by-id/<your-disk-id>'
}
```
Replace the disk path with the actual device ID of your target drive (find it with `ls -l /dev/disk/by-id/`).

### Network
```bash
SYSTEMD_NETWORKD_INTERFACE_NAME='en*'
SYSTEMD_NETWORKD_DHCP='true'            # set to 'false' for static
SYSTEMD_NETWORKD_ADDRESSES='192.168.1.100/32'
SYSTEMD_NETWORKD_GATEWAY='192.168.1.1'
```

### Hostname & locale
```bash
HOSTNAME='myserver.example.com'
TIMEZONE='Europe/Copenhagen'
KEYMAP='us'
LOCALE='en_US.utf8'
```

### SSH authorised keys
```bash
ROOT_SSH_AUTHORIZED_KEYS='ssh-ed25519 AAAA... user@host'
```

---

## Helper scripts

### `reformat_partitions.sh`

Reformats every partition on every disk while preserving its filesystem type, filesystem label, and GPT partition label. Useful for wiping a previously partitioned drive before a fresh install.

```bash
# Preview what would happen
./reformat_partitions.sh --dry-run

# Run interactively (prompts before each disk)
./reformat_partitions.sh

# Run non-interactively
./reformat_partitions.sh --force
```

Requires: `blkid`, `parted`, `wipefs` — all present on the Gentoo minimal CD.

---

## Upstream project

This template depends on **[oddlama/gentoo-install](https://github.com/oddlama/gentoo-install)** for all the heavy lifting. Refer to that project's documentation for advanced configuration options and supported layouts.

---

## Requirements

- Gentoo minimal installation CD (amd64)
- Internet access from the target machine
- `git` available in the live environment (present on the minimal CD)
- Root access
