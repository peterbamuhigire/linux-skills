# Kernel Module Management — Deep Reference

Linux kernel modules are loadable drivers and features (`.ko` files) that the
kernel pulls in on demand. The management tooling ships as the `kmod` package
and is **identical on Debian/Ubuntu and the RHEL family (Fedora, RHEL, CentOS
Stream, Rocky, Alma, Oracle)**. The single per-family difference is the command
used to rebuild the **initramfs** after a boot-time change — covered at the end.

Back to the skill: [`../SKILL.md`](../SKILL.md).

---

## 1. Inspecting modules

### `lsmod` — what is loaded now

```bash
lsmod
```

Output is three columns: **Module**, **Size**, and **Used by** (a usage count
followed by the names of the modules that depend on it). A module with a
non-zero usage count or named dependents cannot simply be unloaded until its
users are gone.

```bash
lsmod | grep -i nouveau     # is the nouveau driver loaded?
```

`lsmod` is a formatted view of `/proc/modules`.

### `modinfo` — details about a module

```bash
modinfo i915
```

Shows the on-disk file path (`filename:`), description, license, dependencies
(`depends:`), aliases, signature, and — importantly — the **parameters** the
module accepts:

```bash
modinfo -p i915             # just the parameter list with descriptions
modinfo -F filename i915    # print one field only (here, the .ko path)
```

### Live parameter values

A loaded module exposes its current parameter values under sysfs:

```bash
ls /sys/module/i915/parameters/
cat /sys/module/i915/parameters/enable_guc
```

Some parameters are writable at runtime (`echo <v> > /sys/module/.../parameters/<p>`),
but most apply only at load time — persist those via `options` (section 4).

---

## 2. Loading and unloading

### Load (with dependencies)

```bash
sudo modprobe br_netfilter
sudo modprobe i915 enable_guc=2      # load with a one-shot parameter
```

`modprobe` resolves and loads dependencies automatically (using
`/lib/modules/$(uname -r)/modules.dep`). Prefer it over the low-level `insmod`,
which loads a single `.ko` by path with no dependency resolution.

### Unload

```bash
sudo modprobe -r br_netfilter        # preferred: unloads + removes now-unused deps
sudo rmmod br_netfilter              # low-level: single module, no dependency logic
```

`modprobe -r` refuses to unload a module that is still in use (non-zero usage
count in `lsmod`). Stop the consumers first, or you will get
`Module ... is in use`.

> From the RHCSA reference material: `modprobe -r` is the correct way to unload a
> module **including all of its dependencies**; `rmmod` is the blunt
> single-module tool and `insmod -r` is not a real unload command.

---

## 3. Loading a module on boot — `/etc/modules-load.d/`

To force a module to load at every boot (when udev/`systemd-udevd` would not
auto-load it), drop a file into `/etc/modules-load.d/` with **one module name
per line**:

```bash
# /etc/modules-load.d/k8s.conf
br_netfilter
overlay
```

`systemd-modules-load.service` reads these early in boot. The system-default
counterpart shipped by packages lives in `/usr/lib/modules-load.d/`; put your
local additions in `/etc/modules-load.d/` so they are not overwritten by
package updates.

To apply immediately without rebooting, also run `sudo modprobe <mod>`.

---

## 4. Module options / parameters — `/etc/modprobe.d/`

Persist load-time parameters with an `options` line in any
`/etc/modprobe.d/*.conf` file. The option applies every time the module loads,
whether at boot or via a manual `modprobe`:

```bash
# /etc/modprobe.d/i915.conf
options i915 enable_guc=2
```

Multiple parameters go on one line: `options <mod> p1=v1 p2=v2`.

System defaults live in `/usr/lib/modprobe.d/`; keep your overrides in
`/etc/modprobe.d/` (which takes precedence). Verify the effect after a reload:

```bash
sudo modprobe -r i915 && sudo modprobe i915
cat /sys/module/i915/parameters/enable_guc
```

> The RHCSA material lists the valid config locations explicitly:
> `/etc/modprobe.d/<somefilename>.conf` and `/usr/lib/modprobe.d/<file>` are
> correct; `/etc/modules.conf` and a bare `/etc/modprobe.conf` are obsolete.

---

## 5. Blacklisting a driver

There are two strengths of "do not load this module," and the difference matters.

### `blacklist <mod>` — block auto-loading by name

```bash
# /etc/modprobe.d/blacklist-nouveau.conf
blacklist nouveau
```

This stops the module from being **auto-loaded by its own name** (e.g. by udev
matching hardware, or `modprobe nouveau` by alias). It does **not** stop the
module from being loaded if another module declares it as a dependency, and it
does not stop an explicit `modprobe nouveau` by an admin.

### `install <mod> /bin/true` — defeat all loads, including dependency loads

```bash
# /etc/modprobe.d/blacklist-nouveau.conf
blacklist nouveau
install nouveau /bin/true
```

The `install` line overrides the *action* taken when anything asks to load
`nouveau`: instead of inserting the module, `modprobe` runs `/bin/true` (a
no-op that exits 0). Because this hijacks the load action itself, it also
suppresses loads pulled in **as a dependency** of another module — which a
plain `blacklist` line does not. Use both lines together when you need a hard
block (the canonical example is replacing the open-source `nouveau` driver with
the NVIDIA proprietary one).

### Verify it took effect

```bash
lsmod | grep nouveau          # should be empty after reboot
modprobe nouveau              # should be silently no-op'd (with install /bin/true)
```

---

## 6. Rebuilding the initramfs (per family)

The **initramfs** is a small early-userspace image the bootloader hands to the
kernel. It contains the drivers needed to reach and mount the **root
filesystem** — typically storage/controller modules, and sometimes network or
crypto modules. Crucially, it carries its **own copy** of the relevant
`/etc/modprobe.d/` and `/etc/modules-load.d/` rules captured at build time.

That means: if the module you are blacklisting or re-parameterizing is loaded
**from the initramfs**, editing `/etc/modprobe.d/` on the running root
filesystem is **not enough** — the initramfs already loaded the old behavior
before your edited config was ever read. You must regenerate the initramfs:

| Family | Rebuild command | Image location |
|---|---|---|
| Debian/Ubuntu | `sudo update-initramfs -u` | `/boot/initrd.img-$(uname -r)` |
| RHEL family | `sudo dracut -f` | `/boot/initramfs-$(uname -r).img` |

### Debian/Ubuntu — `update-initramfs`

```bash
sudo update-initramfs -u                 # update the image for the running kernel
sudo update-initramfs -u -k all          # rebuild for every installed kernel
```

(`update-initramfs` wraps the `initramfs-tools` machinery; `mkinitramfs` is the
lower-level builder.)

### RHEL family — `dracut`

```bash
sudo dracut -f                           # force-rebuild for the running kernel
sudo dracut -f --kver 5.14.0-362.el9     # rebuild for a specific kernel version
sudo dracut -f /boot/initramfs-$(uname -r).img $(uname -r)   # explicit target
```

`dracut` config is layered: `/usr/lib/dracut/dracut.conf.d/*.conf` (defaults),
`/etc/dracut.conf.d/*.conf` (custom), and `/etc/dracut.conf` (master). Per the
RHCSA reference, `dracut` with no arguments re-creates the initramfs for the
currently loaded kernel, and it is also the tool used from a rescue environment
when an initramfs image is damaged.

After either rebuild, the safe sequence is: confirm a fallback kernel/initramfs
exists, confirm console or out-of-band access, then reboot and verify with
`lsmod`.

---

## 7. Safety — why this skill is dangerous to get wrong

- **Storage drivers in the initramfs:** blacklisting the disk/HBA/NVMe
  controller module (or removing it from the initramfs) leaves the kernel
  unable to mount root → kernel panic at boot. Recovery needs rescue media or
  a console.
- **Network drivers on headless/remote hosts:** blacklisting or unloading the
  NIC driver on a box you only reach over SSH cuts you off with no way back in.
- **Forgetting the initramfs rebuild:** for a boot-time module, editing
  `/etc/modprobe.d/` without `update-initramfs -u` / `dracut -f` is a silent
  no-op — the change appears applied but isn't, which is its own trap.

Always: `modinfo`/`lsmod` first, keep a known-good kernel + initramfs to fall
back to, ensure console/IPMI/cloud-console access before rebooting after a
boot-time change, and test the reboot when you can still recover.

---

## See also

- [`../SKILL.md`](../SKILL.md) — the skill entry point and quick command set.
