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

### Build binary packages (`-bb`)

Pass `-bb` to turn the installed system into a binary-package builder:

```bash
./run.sh -bb
```

After the install succeeds, `run.sh` edits the chrooted `/etc/portage/make.conf` to enable `FEATURES="buildpkg"` (preserving any existing features) and to set `BINPKG_COMPRESS="lz4"`, per the [Binary package guide](https://wiki.gentoo.org/wiki/Binary_package_guide#Setting_up_a_binary_package_host). Any other arguments are forwarded to the upstream `./install`.

---

## Continue/Reinstall the packages after rebooting in the new installed system

```bash
cd /tmp ; git clone https://github.com/saitix/gentoo-template.git ; cd gentoo-template ; source gentoo.conf && emerge --verbose --noreplace --jobs=4 --load-average=9 "${ADDITIONAL_PACKAGES[@]}"
```

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
| **Overlay (::guru)** | lsyncd, multitail, nmon, App-perlbrew — _provided by the GURU overlay, which is enabled automatically (see below)_ |
| **Pip (upstream)** | crudini — _not packaged for Gentoo; installed from [github.com/pixelb/crudini](https://github.com/pixelb/crudini) via pip in the `after_install()` hook_ |
| **Portage** | Git sync against `anongit.gentoo.org`, mirrors via `leaseweb`, `ACCEPT_LICENSE="*"`, `-march=native -O2 -pipe`, `-j8 -l9` |

> **GURU overlay:** Some packages above are not in the main `::gentoo` tree. The `after_configure_portage()` hook in `gentoo.conf` automatically installs `app-eselect/eselect-repository`, enables the GURU overlay (`eselect repository enable guru`), and syncs it (`emaint sync -r guru`) — this happens after the main Portage tree is synced but before `ADDITIONAL_PACKAGES` are emerged, so those packages resolve correctly.

---

## Repository layout

```
gentoo-template/
├── gentoo.conf              # Main installer configuration (edit before running)
├── run.sh                   # Entry point — clones upstream and launches install
│                            #   Optional flag: -bb enables binary package
│                            #   building (FEATURES="buildpkg", BINPKG_COMPRESS="lz4")
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

### `run.sh`

Entry point that clones `oddlama/gentoo-install`, overlays `gentoo.conf`, and launches the upstream installer.

```bash
# Plain install
./run.sh

# Install and configure the new system as a binary-package builder
./run.sh -bb

# Any other args are forwarded to the upstream ./install
./run.sh --chroot /tmp/gentoo-install/root
```

When `-bb` is given, the chrooted `/etc/portage/make.conf` is updated after install to enable `FEATURES="buildpkg"` (existing features are preserved) and to set `BINPKG_COMPRESS="lz4"`.

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
