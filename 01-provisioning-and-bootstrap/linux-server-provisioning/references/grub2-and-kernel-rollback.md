# GRUB2 + Kernel Lifecycle and Rollback

**Author:** Peter Bamuhigire · [techguypeter.com](https://techguypeter.com) · +256 784 464 178

The bootloader is the one piece of provisioning that, if you get it wrong, the
box does not come back. This reference covers the GRUB2 configuration model for
both families, listing and setting the default kernel, editing kernel command
line (boot) parameters, and the production-critical workflow: **rolling back to
a known-good kernel after a panic**.

This is the *boot-time* counterpart to `linux-disaster-recovery`, which covers
GRUB *regeneration after corruption* and initramfs/filesystem repair from a
rescue environment. Use this reference when the system still boots (even into
an older kernel) and you need to manage which kernel and parameters it uses.
Use `linux-disaster-recovery` when GRUB itself is broken or unbootable.

## Table of contents

1. The GRUB2 config model per family
2. Listing installed kernels
3. Setting and listing the default kernel
4. Editing kernel boot parameters (cmdline)
5. Kernel lifecycle: install, keep N, remove
6. Rolling back to a known-good kernel after a panic
7. Serial console and timeout basics
8. The sk-kernel-rollback helper
9. Sources

---

## 1. The GRUB2 config model per family

GRUB2 is **never edited at the generated `grub.cfg`** directly — that file is
machine-generated and overwritten on every kernel update. You edit the *inputs*
(`/etc/default/grub` and the `/etc/grub.d/` scripts) and then **regenerate** the
config. The regeneration command and output path are the main family
differences.

| Concept | Debian/Ubuntu | RHEL family |
|---|---|---|
| Editable input | `/etc/default/grub` | `/etc/default/grub` |
| Drop-in scripts | `/etc/grub.d/` | `/etc/grub.d/` |
| Regenerate command | `update-grub` (wraps `grub-mkconfig`) | `grub2-mkconfig -o <cfg>` |
| Generated config (BIOS) | `/boot/grub/grub.cfg` | `/boot/grub2/grub.cfg` |
| Generated config (UEFI) | `/boot/grub/grub.cfg` | `/boot/efi/EFI/<distro>/grub.cfg` (`redhat`, `centos`, `rocky`, `almalinux`, `fedora`, `oracle`) |
| Per-kernel/cmdline edits | edit `/etc/default/grub` + regenerate | `grubby` (live edits, no full regen) |
| Set default kernel | `grub-set-default` / edit `GRUB_DEFAULT` | `grubby --set-default` / `grub2-set-default` |

The most important line in `/etc/default/grub` on both families is
`GRUB_CMDLINE_LINUX`, which holds the kernel boot arguments. A default RHEL
file looks like:

```
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="$(sed 's, release .*$,,g' /etc/system-release)"
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL_OUTPUT="console"
GRUB_CMDLINE_LINUX="crashkernel=auto resume=/dev/mapper/rhel-swap rd.lvm.lv=rhel/root rd.lvm.lv=rhel/swap rhgb quiet"
GRUB_DISABLE_RECOVERY="true"
GRUB_ENABLE_BLSCFG=true
```

`GRUB_DEFAULT=saved` means "boot whatever kernel was saved as the default" — this
is what `grub2-set-default` / `grub-set-default` write to. `GRUB_ENABLE_BLSCFG=true`
(RHEL 8+) means kernels are managed as **BootLoader Spec (BLS)** entries under
`/boot/loader/entries/`, which is why `grubby` can edit them live without a full
`grub2-mkconfig` run.

**Regenerate after editing `/etc/default/grub`:**

```bash
# Debian/Ubuntu — path is figured out for you
sudo update-grub

# RHEL family — you must name the output path
sudo grub2-mkconfig -o /boot/grub2/grub.cfg          # BIOS
sudo grub2-mkconfig -o /boot/efi/EFI/rocky/grub.cfg   # UEFI (adjust distro dir)
```

To find the right RHEL output path automatically:

```bash
[ -d /sys/firmware/efi ] \
  && echo "/boot/efi/EFI/$(. /etc/os-release; echo "$ID")/grub.cfg" \
  || echo "/boot/grub2/grub.cfg"
```

---

## 2. Listing installed kernels

GRUB2 picks up every kernel it finds in `/boot` automatically and adds it to the
menu, so listing installed kernels tells you what you can boot or roll back to.

```bash
# Debian/Ubuntu — installed kernel packages, newest last
dpkg --list 'linux-image-*' | grep '^ii'
ls -1 /boot/vmlinuz-*

# RHEL family — installed kernel RPMs and boot entries
rpm -q kernel
sudo grubby --info=ALL | grep -E 'index|kernel|title'
ls -1 /boot/vmlinuz-*
```

The currently running kernel is always `uname -r`. A kernel listed in `/boot`
that is **not** equal to `uname -r` is a candidate to boot into or set default.

---

## 3. Setting and listing the default kernel

**RHEL family** (prefer `grubby` — it is BLS-aware):

```bash
# Show the current default
sudo grubby --default-kernel        # prints the path, e.g. /boot/vmlinuz-5.14.0-...
sudo grubby --default-index         # prints the menu index (0 = first)

# Set the default by full kernel path
sudo grubby --set-default /boot/vmlinuz-5.14.0-70.13.1.el9_0.x86_64

# Or set by index (matches the boot-menu order)
sudo grubby --set-default-index=1

# Lower-level alternative when GRUB_DEFAULT=saved
sudo grub2-set-default "Rocky Linux (5.14.0-70.13.1.el9_0.x86_64) 9.0"
sudo grub2-editenv list             # confirm the saved_entry value
```

**Debian/Ubuntu:**

```bash
# List menu entries (index and title) as GRUB sees them
grep -E "^menuentry|^submenu" /boot/grub/grub.cfg | cut -d"'" -f2 | nl -v0

# Set the default by index or by the exact saved-entry id
sudo grub-set-default 0
# For a kernel inside the "Advanced options" submenu, use the saved id form:
sudo grub-set-default "gnulinux-advanced-XXXX>gnulinux-5.15.0-91-generic-advanced-XXXX"
sudo update-grub                    # rewrite grub.cfg so the choice sticks
```

For the choice to be honored, `GRUB_DEFAULT=saved` must be set in
`/etc/default/grub` (it is the default on RHEL; on Debian set it and run
`update-grub`).

---

## 4. Editing kernel boot parameters (cmdline)

**RHEL family** — `grubby` edits cmdline live, per-kernel or for all, no full
regen needed:

```bash
# Add an argument to every installed kernel (persistent)
sudo grubby --update-kernel ALL --args "selinux=0"

# Remove it again
sudo grubby --update-kernel ALL --remove-args "selinux"

# Target only the running kernel
sudo grubby --update-kernel "$(grubby --default-kernel)" --args "transparent_hugepage=never"

# Inspect the effective args for a kernel
sudo grubby --info="$(grubby --default-kernel)"
```

**Debian/Ubuntu** — edit `GRUB_CMDLINE_LINUX` (or
`GRUB_CMDLINE_LINUX_DEFAULT`) in `/etc/default/grub`, then regenerate:

```bash
sudo sed -i 's/\(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*\)"/\1 transparent_hugepage=never"/' /etc/default/grub
sudo update-grub
```

**One-time, non-persistent** edits (both families): at the GRUB menu, press `e`,
edit the `linux` line, and press `Ctrl-X` to boot. These changes are **not**
saved — useful for testing a parameter or booting once with `rhgb quiet`
removed to see boot messages. Removing `rhgb` and `quiet` permanently (via the
above) is recommended on servers so you can see what is happening at boot.

---

## 5. Kernel lifecycle: install, keep N, remove

Installing a new kernel **adds it alongside** the old one and makes it the new
default; the old kernel stays bootable. This is the safety net that makes
rollback possible — never let it get pruned to a single kernel.

```bash
# RHEL family — install/upgrade keeps the old kernel automatically
sudo dnf upgrade kernel        # or: dnf install kernel
# /boot keeps the last N kernels; N is installonly_limit in /etc/dnf/dnf.conf
grep installonly_limit /etc/dnf/dnf.conf      # default 3

# Debian/Ubuntu — keeps multiple; autoremove prunes only kernels APT marked
sudo apt install --reinstall "linux-image-$(uname -r)"   # repair current
sudo apt autoremove --purge                              # prune old (keeps current + 1)
```

> **Do not** `dnf install kernel` then immediately remove the previous one. Keep
> at least one prior known-good kernel until the new one has survived a reboot
> and a load test. `installonly_limit` of 3 (RHEL) gives you that headroom.

Remove a specific bad kernel **only after** you have booted a good one and made
it the default (see next section):

```bash
# RHEL family
sudo dnf remove kernel-5.14.0-BAD.el9.x86_64

# Debian/Ubuntu
sudo apt purge linux-image-5.15.0-BAD-generic
```

---

## 6. Rolling back to a known-good kernel after a panic

This is the production scenario: a kernel update (or a bad cmdline change)
causes a **kernel panic** or an unbootable system. The fix uses the prior kernel
GRUB kept for exactly this reason.

**Step 1 — Boot the prior kernel from the GRUB menu (one time).**
Reboot. At the GRUB menu, select **Advanced options for <distro>** and choose
the previous kernel version. On a console you may need to press `Esc`/`Shift`
during boot to reveal the menu (see timeout in §7). This boots the good kernel
*once*; it is not yet the default.

**Step 2 — Confirm you are on the good kernel.**

```bash
uname -r        # should show the older, working version
```

**Step 3 — Make the good kernel the default** so the next reboot is safe:

```bash
# RHEL family
sudo grubby --set-default "/boot/vmlinuz-$(uname -r)"
sudo grubby --default-kernel        # verify

# Debian/Ubuntu — find the running kernel's menu index, set it, regenerate
sudo grub-set-default 0             # or the exact saved-entry id from §3
sudo update-grub
```

Or use the helper, which does the list-and-set safely with confirmation:

```bash
sudo sk-kernel-rollback              # interactive: pick a prior kernel, confirm
sudo sk-kernel-rollback --list       # read-only listing
```

**Step 4 — Remove or blacklist the bad kernel** so it cannot be selected again
and a future update does not re-promote it:

```bash
# RHEL family — remove the bad kernel package
sudo dnf remove kernel-core-5.14.0-BAD.el9.x86_64

# Debian/Ubuntu — purge the bad image, then hold the version that broke
sudo apt purge linux-image-5.15.0-BAD-generic
sudo apt-mark hold linux-image-5.15.0-BAD-generic    # belt-and-braces

# RHEL — exclude a known-bad version from future installs
echo 'exclude=kernel-5.14.0-BAD*' | sudo tee -a /etc/dnf/dnf.conf
```

**Step 5 — Regenerate and reboot to verify** the box now comes up unattended on
the good kernel:

```bash
sudo grub2-mkconfig -o /boot/grub2/grub.cfg    # RHEL (or update-grub on Debian)
sudo reboot
# after reboot:
uname -r        # confirm the good kernel booted with no menu interaction
```

If GRUB itself will not load (not just the kernel), this is beyond rollback —
boot rescue media and follow **`linux-disaster-recovery`** for `grub2-install`,
`grub2-mkconfig` regeneration, and `dracut`/`update-initramfs` rebuilds.

---

## 7. Serial console and timeout basics

For remote/headless servers you usually want a longer GRUB timeout (so you can
catch the menu over a slow console) and serial console output for out-of-band
access (IPMI/SOL, cloud serial console).

Edit `/etc/default/grub`:

```
# Wait long enough to interrupt the menu over a slow link
GRUB_TIMEOUT=10
# Show the menu rather than hiding it (helps during rollback)
GRUB_TIMEOUT_STYLE=menu

# Serial console: send GRUB + kernel output to ttyS0 as well as the screen
GRUB_TERMINAL="console serial"
GRUB_SERIAL_COMMAND="serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1"
```

Add the matching kernel arg so the OS also uses the serial line (last `console=`
wins for the boot log):

```bash
# RHEL family
sudo grubby --update-kernel ALL --args "console=tty0 console=ttyS0,115200n8"
# Debian/Ubuntu: append the same to GRUB_CMDLINE_LINUX, then:
sudo update-grub
```

Then regenerate (`update-grub` / `grub2-mkconfig -o …`). A short timeout (0–1s)
is convenient on fast cloud instances but makes manual rollback harder — bump it
to 5–10s on any host you might have to recover by hand.

---

## 8. The sk-kernel-rollback helper

`sk-kernel-rollback` is the convenience wrapper for §6 step 3. It is **never
required** — every action above is a plain command — but it removes the
error-prone parts (matching kernel paths/indices to titles) and always confirms
before changing the default.

- `sudo sk-kernel-rollback --list` — read-only. Lists installed kernels, marks
  the running one and the current default, on either family.
- `sudo sk-kernel-rollback` — interactive. Lists prior kernels, lets you pick
  one, shows exactly what it will do, and sets it as the GRUB default **after you
  confirm** (`grubby --set-default` on RHEL; `grub-set-default` + `update-grub`
  on Debian). It regenerates config only on the family that needs it.
- `sudo sk-kernel-rollback --to <version>` — non-interactive target by `uname -r`
  style version string.

It uses the `common.sh` contract: `set -uo pipefail`, `require_root` for the
mutate path, `detect_distro`/`require_family any`, `confirm` before applying,
`--dry-run` to preview, and an audit-log entry on change.

---

## 9. Sources

- Sander van Vugt, *Red Hat RHCSA 8 Cert Guide (EX200)* — Working with GRUB 2:
  `/etc/default/grub`, `GRUB_CMDLINE_LINUX`, `GRUB_TIMEOUT`, `GRUB_DEFAULT=saved`,
  `grub2-mkconfig -o /boot/grub2/grub.cfg` (BIOS) and the UEFI
  `/boot/efi/EFI/<distro>/grub.cfg` path; one-time menu edits via `e` + `Ctrl-X`.
- Sander van Vugt, *Red Hat RHCSA 10 Cert Guide (EX200)* — Upgrading the Linux
  kernel (install keeps the old kernel; `/boot` retains the last kernels; GRUB2
  auto-picks them up so you can boot an older kernel if a new one fails);
  `grubby --update-kernel ALL --args/--remove-args` for persistent cmdline edits.
- *Mastering Debian* / Debian GRUB docs — `update-grub` wrapping `grub-mkconfig`,
  `/boot/grub/grub.cfg`, `grub-set-default`, `GRUB_CMDLINE_LINUX_DEFAULT`.
- See also: [`../../09-troubleshooting-and-recovery/linux-disaster-recovery/SKILL.md`](../../../09-troubleshooting-and-recovery/linux-disaster-recovery/SKILL.md)
  for GRUB regeneration after corruption and initramfs/filesystem repair.
