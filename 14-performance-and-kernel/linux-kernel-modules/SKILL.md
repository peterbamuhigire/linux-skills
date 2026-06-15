---
name: linux-kernel-modules
description: Manage Linux kernel modules (drivers) across both major families — Debian/Ubuntu and the RHEL family (Fedora, RHEL, CentOS Stream, Rocky, Alma, Oracle). Inspect loaded modules (lsmod, modinfo), load and unload them (modprobe, modprobe -r / rmmod), load modules on boot via /etc/modules-load.d/*.conf, set module options/parameters via /etc/modprobe.d/*.conf (options <mod> ...), and blacklist drivers (blacklist <mod>, and the stronger install <mod> /bin/true). Rebuild the initramfs after blacklisting a boot-time module: update-initramfs -u on Debian/Ubuntu vs dracut -f on the RHEL family. The module tooling is identical across families; only the initramfs rebuild command differs.
license: MIT
metadata:
  author: Peter Bamuhigire
  author_url: techguypeter.com
  author_contact: "+256784464178"
---
# Kernel Module Management

## Distro support

One-family-tool skill. The module commands (`lsmod`, `modinfo`, `modprobe`,
`modprobe -r`/`rmmod`) and the config directories (`/etc/modules-load.d/`,
`/etc/modprobe.d/`) are part of `kmod` and are **identical on both families**.
The only thing that differs is the command used to **rebuild the initramfs**
after you blacklist or change options for a module that loads at boot. Body
uses the common tooling; substitute the initramfs command per this matrix.

| Concept | Debian/Ubuntu | RHEL family |
|---|---|---|
| List loaded modules | `lsmod` | `lsmod` |
| Module info / params | `modinfo <mod>` | `modinfo <mod>` |
| Load module (+deps) | `modprobe <mod>` | `modprobe <mod>` |
| Unload module | `modprobe -r <mod>` / `rmmod <mod>` | `modprobe -r <mod>` / `rmmod <mod>` |
| Load on boot | `/etc/modules-load.d/<x>.conf` | `/etc/modules-load.d/<x>.conf` |
| Module options | `/etc/modprobe.d/<x>.conf` (`options <mod> ...`) | `/etc/modprobe.d/<x>.conf` (`options <mod> ...`) |
| Blacklist a driver | `/etc/modprobe.d/<x>.conf` (`blacklist <mod>`) | `/etc/modprobe.d/<x>.conf` (`blacklist <mod>`) |
| **Rebuild initramfs** | `sudo update-initramfs -u` | `sudo dracut -f` |

The split matters because `blacklist`/`options` lines in `/etc/modprobe.d/`
are only consulted at boot if they are also baked into the **initramfs** — the
early-userspace image that loads storage and root-filesystem drivers before
`/etc` is available. Editing `/etc/modprobe.d/` alone does not change a module
that the initramfs already loads. Full detail, including the per-family
initramfs mechanics, is in
[`references/module-management.md`](references/module-management.md).

## Use when

- Inspecting which drivers/modules are loaded and with what parameters.
- Loading or unloading a kernel module by hand or persisting it across reboots.
- Setting a module option/parameter (e.g. a NIC or sound driver tweak).
- Blacklisting a problematic or conflicting driver.

## Do not use when

- The task is sysctl / runtime kernel parameter tuning; use `linux-sysctl-tuning`.
- The task is profiling CPU/IO/perf hot paths; use `linux-perf-profiling`.
- GRUB or initramfs is already broken and the box won't boot; use
  `linux-disaster-recovery`.

## Required inputs

- The module name(s) involved and what you intend to do (inspect, load,
  unload, set an option, blacklist).
- Whether the change must survive a reboot.
- Whether the module is needed at **boot time** (storage/root-fs, network on a
  headless/remote host) — this decides whether an initramfs rebuild is required
  and raises the safety stakes.

## Workflow

1. Inspect first: `lsmod` to see what is loaded, `modinfo <mod>` for params,
   dependencies, and the file path.
2. Make the change — load/unload at runtime, or write a `/etc/modules-load.d/`
   or `/etc/modprobe.d/` file for persistence.
3. If you blacklisted or changed options for a **boot-time** module, rebuild
   the initramfs (`update-initramfs -u` / `dracut -f`).
4. Verify: re-run `lsmod`, confirm the parameter under
   `/sys/module/<mod>/parameters/`, and (for boot-time changes) confirm a
   clean reboot — ideally with console/out-of-band access available.

## Quality standards

- Always `modinfo` and `lsmod` before unloading or blacklisting.
- Persist intent in `/etc/modprobe.d/` or `/etc/modules-load.d/` rather than
  relying on one-off runtime `modprobe` commands.
- Treat any boot-time module change as a change that requires an initramfs
  rebuild and a tested reboot.

## Anti-patterns

- Blacklisting a storage or network driver on a remote/headless box with no
  console fallback — a classic way to make a machine unbootable or unreachable.
- Editing `/etc/modprobe.d/` for a boot-time module and forgetting to rebuild
  the initramfs (the change silently does nothing).
- Using `rmmod` (no dependency handling) where `modprobe -r` is safer.

## Safety note

Blacklisting or unloading the wrong module is one of the easiest ways to brick
a server. A blacklisted **storage** driver (e.g. the disk controller) can leave
the kernel unable to mount the root filesystem — the box panics at boot. A
blacklisted or unloaded **network** driver on a headless/remote host cuts you
off with no way back in over SSH. Before blacklisting a boot-time driver:
confirm you have console or out-of-band (IPMI/iLO/cloud-console) access, keep a
known-good kernel/initramfs to fall back to, and test the reboot when you can
recover from a failure.

## Outputs

- What was inspected, loaded, unloaded, or blacklisted, and where it was
  persisted.
- Whether an initramfs rebuild was required and which command was run.
- The verification performed (re-`lsmod`, `/sys/module/.../parameters/`,
  reboot test) and any remaining boot/connectivity risk.

## References

- [`references/module-management.md`](references/module-management.md) — deep
  reference: inspect/load/unload, load-on-boot, options/parameters, blacklisting
  (`blacklist` vs `install <mod> /bin/true`), and the per-family initramfs
  rebuild detail with examples.

**This skill is self-contained.** Every command below is a standard `kmod`
tool present on both families; only the initramfs rebuild command differs per
the **Distro support** matrix. The `sk-module-info` script in the **Optional
fast path** section is a read-only convenience wrapper — never required.

## Inspect modules

```bash
lsmod                                 # all loaded modules, size, usage count, users
lsmod | grep -i <name>                # is a specific module loaded?
modinfo <mod>                         # description, params, deps, file path, signature
modinfo -p <mod>                      # just the supported parameters
cat /sys/module/<mod>/parameters/<p>  # current live value of a parameter
```

## Load / unload at runtime

```bash
sudo modprobe <mod>                   # load module AND its dependencies
sudo modprobe <mod> <param>=<value>   # load with a one-shot parameter
sudo modprobe -r <mod>                # unload, honoring dependency order (preferred)
sudo rmmod <mod>                      # unload a single module, no dep handling
```

Runtime changes do **not** survive a reboot — persist them below.

## Load a module on boot

Create a file in `/etc/modules-load.d/` with one module name per line:

```bash
echo 'br_netfilter' | sudo tee /etc/modules-load.d/br_netfilter.conf
# Applied by systemd-modules-load.service at next boot (or load now with modprobe).
```

## Set module options / parameters (persistent)

Use `options` in a `/etc/modprobe.d/*.conf` file — applied whenever the module
is loaded (boot or manual):

```bash
# /etc/modprobe.d/i915.conf
options i915 enable_guc=2
```

If the module loads from the **initramfs** (boot-time driver), rebuild it so the
option is baked in — see below.

## Blacklist a driver

```bash
# /etc/modprobe.d/blacklist-nouveau.conf
blacklist nouveau                 # stops modprobe from auto-loading 'nouveau'
install nouveau /bin/true         # STRONGER: runs /bin/true instead of loading it,
                                  # also defeating loads pulled in as a dependency
```

`blacklist` only blocks the module from being auto-loaded by name; another
module that lists it as a dependency can still pull it in. `install <mod>
/bin/true` overrides the load action entirely, so even dependency-triggered
loads become a no-op — use it when `blacklist` alone is not enough.

## Rebuild the initramfs after a boot-time change

Blacklisting or re-parameterizing a module that the initramfs loads only takes
effect once you regenerate that image:

```bash
sudo update-initramfs -u            # Debian/Ubuntu (rebuilds current kernel's image)
sudo dracut -f                      # RHEL family (force-rebuild current kernel's image)
```

> Boot-time module changes can make a host unbootable or unreachable. See the
> **Safety note** above — confirm console/out-of-band access and a fallback
> kernel before rebooting.

---

## Optional fast path (when sk-* scripts are installed)

Running `sudo install-skills-bin linux-kernel-modules` installs:

| Task | Fast-path script |
|---|---|
| List loaded modules or show `modinfo <mod>` (read-only) | `sk-module-info [<mod>]` |
| Print (do NOT apply) the exact blacklist steps for a module | `sk-module-info --blacklist <mod>` |

This is an optional read-only wrapper. The `lsmod` / `modinfo` / `modprobe`
commands above are the source of truth.

## Scripts

This skill installs the following scripts to `/usr/local/bin/`. To install:

```bash
sudo install-skills-bin linux-kernel-modules
```

| Script | Source | Core? | Purpose |
|---|---|---|---|
| sk-module-info | scripts/sk-module-info.sh | yes | Read-only: list loaded modules (`lsmod`) or show `modinfo <mod>`. With `--blacklist <mod>` it only PRINTS the exact blacklist + initramfs-rebuild steps for the detected family; it never applies them unless explicitly confirmed. |
