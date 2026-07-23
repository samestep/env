# env [![Build](https://github.com/samestep/env/actions/workflows/build.yml/badge.svg)](https://github.com/samestep/env/actions/workflows/build.yml) [![Update](https://github.com/samestep/env/actions/workflows/update.yml/badge.svg)](https://github.com/samestep/env/actions/workflows/update.yml)

My [Nix](https://nixos.org/) environment. Once you have Nix installed, the first step is to clone this repo:

```sh
nix-shell -p git gh --run "gh auth login && gh repo clone samestep/env ~/github/samestep/env"
```

There are separate configurations for the two different machines I use.

## [NixOS](nixos)

This machine has an x86 CPU and an NVIDIA GPU, and runs NixOS.

Run these commands to setup the NixOS configuration:

```sh
cp /etc/nixos/hardware-configuration.nix ~/github/samestep/env/nixos/nixos/
sudo rm /etc/nixos/*
sudo ln -s ~/github/samestep/env/flake.nix /etc/nixos/flake.nix
sudo nixos-rebuild switch
sudo nix-channel --remove nixos
```

Then run these commands to setup the Home Manager configuration:

```sh
ln -fsT ~/github/samestep/env ~/.config/home-manager
nix run ~/github/samestep/env#home-manager switch
```

You may need to log out and back in to see everything installed in the GNOME applications launcher.

## [macOS](macos)

This machine has an Apple Silicon chip and runs macOS.

[Enable flakes][flakes] by making sure this line is present in `/etc/nix/nix.conf`:

```
experimental-features = nix-command flakes
```

Then run these commands to setup the Home Manager configuration:

```sh
rm -rf ~/.config/home-manager
ln -s ~/github/samestep/env ~/.config/home-manager
nix run ~/github/samestep/env#home-manager switch
```

## [libvirt](sandbox-amd64)

This config can also be used for x86 Linux virtual machines on Linux. First make sure you have [virt-manager](https://virt-manager.org/), virt-viewer, and the [libvirt NSS module](https://libvirt.org/nss.html) installed, as they are in this repo's NixOS config. Then make sure you've started the `default` network:

```sh
virsh -c qemu:///system net-start default
```

You can also run this command so the `default` network starts automatically in the future:

```sh
virsh -c qemu:///system net-autostart default
```

Download an OS ISO like [Ubuntu 26.04](https://releases.ubuntu.com/26.04/) and run this command to create a VM, tweaking the CPU/RAM/disk parameters as appropriate:

```sh
virt-install --connect qemu:///system --name sandbox-amd64 --vcpus 32 --memory 65536 --disk size=1000 --network network=default --cdrom ubuntu-26.04-live-server-amd64.iso
```

As a heads up, at time of writing, the only reason Ubuntu 26.04 works for me here is because I'm using an [unreleased osinfo-db patch](https://gitlab.com/libosinfo/osinfo-db/-/commit/6f01a968803a30c7e5da631b0205c5982b20b842) that adds support for it. You may need to use an image of an older OS instead.

That aside, here's what all the flags mean:

- the `--connect` setting makes the `default` network visible
- the explicit `--name` is used by the `libvirt_guest` NSS module for SSH
- `--vcpus` allows the VM to use all the cores instead of just two
- `--memory` is in MiB
- `--disk size` is in GB
- the `--network` setting is necessary for SSH to work after installation

When installing Ubuntu, in the "Storage configuration" step, increase the size of the `ubuntu-lv` device from `100.000G` to the maximum allowed, which will depend on how much disk space you gave it. Then use these options in the "Profile configuration" step:

- Your name: `Agent`
- Your servers name: `sandbox-amd64`
- Pick a username: `agent-amd64`
- Choose a password: `password`
- Confirm your password: `password`

Check the "Install OpenSSH server" box in the "SSH configuration" step. Then once installation is finished, ignore the message saying to remove the installation medium, and just hit ENTER to reboot.

After rebooting, you can close the virt-viewer window; you won't need it again. Next, give the VM your public SSH key so you don't need to type the password when connecting:

```sh
ssh-copy-id agent-amd64@sandbox-amd64
```

Now connect using SSH:

```sh
ssh agent-amd64@sandbox-amd64
```

The only reason for choosing a password at all was because the Ubuntu installer forces you to; first step after installation is to enable passwordless `sudo`:

```sh
echo "agent-amd64 ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/agent && sudo chmod 0440 /etc/sudoers.d/agent
```

The next step is to reconfigure chrony so that it can readjust the VM's clock if it becomes wrong e.g. if the host machine reboots. Make this edit to `/etc/chrony/chrony.conf`:

```diff
-makestep 1 3
+makestep 1 -1
```

Note that the above may be unnecessary if you configure libvirt to shut down VMs when you shut down the host machine. That may be a good idea in general, since if libvirt only suspends and resumes the VMs when the host machine reboots, their DHCP leases can disappear from the host, forcing you to use an explicit IP address for SSH.

Then install Nix:

```sh
sh <(curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install) --daemon
```

Enable [flakes][]:

```sh
echo 'experimental-features = nix-command flakes' | sudo tee -a /etc/nix/nix.conf
```

After installing Nix you'll need to log back out and back in. Then clone this repo:

```sh
git clone https://github.com/samestep/env.git ~/github/samestep/env
```

And set up the Home Manager symlink:

```sh
mkdir ~/.config && ln -fsT ~/github/samestep/env ~/.config/home-manager
```

And finally set up the Home Manager config itself:

```sh
nix run ~/github/samestep/env#home-manager -- switch -b backup
```

As an optional followup step, install Tailscale to be able to talk to other VMs; installing via Home Manager doesn't work properly on Ubuntu, so just use the official installer:

```sh
curl -fsSL https://tailscale.com/install.sh | sh
```

Connect to the tailnet:

```sh
sudo tailscale up --ssh --hostname=sandbox-amd64
```

And run this repo's script to generate `~/.ssh/tailnet`:

```sh
tailnet
```

## [Tart (Linux)](ubuntu)

This config can be used for ARM Linux virtual machines on macOS, via [Tart](https://tart.run/) which comes with the host-side macOS config in this repo. First, download an Ubuntu image:

```sh
tart clone ghcr.io/cirruslabs/ubuntu:latest ubuntu
```

By default, Tart doesn't give the VM all CPU cores, and only gives 8 GiB of RAM and 50 GB of disk space, so adjust those as appropriate:

```sh
tart set ubuntu --cpu 18 --memory 32768 --disk-size 2000
```

Start up the VM, optionally using the [`--nested`](https://tart.run/faq/#nested-virtualization-support) flag to enable KVM:

```sh
tart run --no-graphics --nested ubuntu
```

Leave that running and, in a different terminal, give the VM your public SSH key give the VM your public SSH key so you don't need to type the password each time you connect:

```sh
ssh-copy-id admin@$(tart ip ubuntu)
```

While adding the SSH key, you will need to type the password, which is `admin`. Then SSH into the VM:

```sh
ssh admin@$(tart ip ubuntu)
```

Avoid ten-second hangs by enabling Ubuntu to resolve the local hostname:

```sh
echo "127.0.1.1 $(hostname)" | sudo tee -a /etc/hosts
```

Next, install Nix:

```sh
sh <(curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install) --daemon
```

Enable [flakes][]:

```sh
echo 'experimental-features = nix-command flakes' | sudo tee -a /etc/nix/nix.conf
```

After installing Nix you'll need to log back out and back in. Then clone this repo:

```sh
git clone https://github.com/samestep/env.git ~/github/samestep/env
```

Make a symlink for Home Manager:

```sh
mkdir -p ~/.config && ln -fsT ~/github/samestep/env ~/.config/home-manager
```

And activate the config:

```sh
nix run ~/github/samestep/env#home-manager -- switch -b backup
```

As an optional followup step, install Tailscale to be able to talk to other VMs; installing via Home Manager doesn't work properly on Ubuntu, so just use the official installer:

```sh
curl -fsSL https://tailscale.com/install.sh | sh
```

Connect to the tailnet:

```sh
sudo tailscale up --ssh --hostname=ubuntu
```

And run this repo's script to generate `~/.ssh/tailnet`:

```sh
tailnet
```

## [Tart (macOS)](tahoe-vanilla)

This config can be used for macOS VMs, again using [Tart](https://tart.run/). First, download a macOS image:

```sh
tart clone ghcr.io/cirruslabs/macos-tahoe-vanilla:latest tahoe-vanilla
```

Expand the provided CPU cores, RAM, and disk space:

```sh
tart set tahoe-vanilla --cpu 18 --memory 16384 --disk-size 1000
```

Next follow the [steps to finish resizing the disk of a macOS Tart VM](https://tart.run/faq/#disk-resizing), starting by booting in recovery mode:

```sh
tart run --recovery tahoe-vanilla
```

Choose Options, then open the Terminal under Utilities. Delete the preexisting recovery partition:

```sh
diskutil eraseVolume free free disk0s3
```

Repair the disk:

```sh
yes | diskutil repairDisk disk0
```

And resize the system Apple File System container to use the new disk space:

```sh
diskutil apfs resizeContainer disk0s2 0
```

Shut down the VM, then reboot it:

```sh
tart run tahoe-vanilla
```

Since we're using the vanilla image, we still need to install the Xcode Command Line Tools:

```sh
xcode-select --install
```

That should pop up a dialogue which you need to accept. You'll also want to [allow Ghostty's environment forwarding over SSH](https://ghostty.org/docs/features/shell-integration#remote-sshd-configuration):

```sh
echo AcceptEnv COLORTERM TERM_PROGRAM TERM_PROGRAM_VERSION | sudo tee /etc/ssh/sshd_config.d/101-color.conf
```

Now shut down the VM again and reboot it once more, this time without graphics:

```sh
tart run --no-graphics tahoe-vanilla
```

In a different terminal, give the VM your public SSH key, using the password `admin`:

```sh
ssh-copy-id admin@$(tart ip tahoe-vanilla)
```

Then SSH into the VM:

```sh
ssh admin@$(tart ip tahoe-vanilla)
```

[Install Nix](https://github.com/DeterminateSystems/nix-installer/tree/v3.20.0#install-determinate-nix):

```sh
curl -fsSL https://install.determinate.systems/nix | sh -s -- install
```

You may need to start a new shell. Clone this repo:

```sh
git clone https://github.com/samestep/env.git ~/github/samestep/env
```

Set up the Home Manager symlink:

```sh
mkdir -p ~/.config && ln -s ~/github/samestep/env ~/.config/home-manager
```

And finally activate the Home Manager config:

```sh
nix run ~/github/samestep/env#home-manager switch
```

As an optional followup step, activate Tailscale to let other VMs connect to this one; the Home Manager config provides the open-source tailscaled variant since that's the only macOS one with an SSH server, but it still needs to be registered with launchd:

```sh
sudo "$(command -v tailscaled)" install-system-daemon
```

Connect to the tailnet:

```sh
sudo tailscale up --ssh --hostname=tahoe-vanilla
```

Note that, without additional setup, this VM can only receive Tailscale SSH connections, and cannot SSH into other VMs on the tailnet.

## Nix remote builders

The `ubuntu` VM (`aarch64-linux`) coordinates builds across the tailnet,
offloading `x86_64-linux` to `sandbox-amd64` and `aarch64-darwin` to
`tahoe-vanilla` over Tailscale SSH. This is what `npd -s x86_64-linux -s
aarch64-linux -s aarch64-darwin` relies on. Beyond the SSH setup above, there are
two non-obvious gotchas: declaring each builder's capabilities, and Ubuntu's
AppArmor user-namespace restriction.

### Declaring the builders

On the coordinator, point `/etc/nix/nix.conf` at a machines file:

```
builders = @/etc/nix/machines
builders-use-substitutes = false
```

and list one builder per line in `/etc/nix/machines`:

```
ssh://admin@tahoe-vanilla.tail1a09f6.ts.net aarch64-darwin - 6 1 big-parallel,benchmark - <base64 host key>
ssh://agent-amd64@sandbox-amd64.tail1a09f6.ts.net x86_64-linux - 8 1 big-parallel,benchmark,kvm,nixos-test,uid-range - <base64 host key>
```

The fields are `URI system ssh-key max-jobs speed-factor features
mandatory-features base64-host-key`. SSH goes through the `~/.ssh/tailnet` config
(from the `tailnet` script), connecting as the user in each URI; because the
nix-daemon runs builds as root, root — not just your user — must be able to reach
each builder.

The **features** field (6th) is the gotcha. Nix only dispatches a derivation to a
builder whose line advertises **every** feature in the derivation's
`requiredSystemFeatures`. NixOS VM tests — e.g. `lixPackageSets.*.lix.tests.misc`
and `.lix.tests.installer` — set `requiredSystemFeatures = [ "kvm" "nixos-test" ]`,
so the `x86_64-linux` line must advertise both (plus `uid-range`, used by some
sandbox tests). If it doesn't, those derivations have no eligible builder and npd
reports them as `❔` ("couldn't try to build") — even though `sandbox-amd64` fully
supports them. Match the list to what the builder actually offers, which you can
read on the builder itself:

```sh
ssh sandbox-amd64 'nix show-config | grep system-features'
# system-features = benchmark big-parallel kvm nixos-test uid-range
```

The `tahoe-vanilla` line deliberately omits `kvm`/`nixos-test`: it can't run Linux
VM tests. After editing `/etc/nix/machines`, restart the daemon so it re-reads the
file:

```sh
sudo systemctl restart nix-daemon
```

### Capping build parallelism for memory

Each builder runs with `cores = 0`, i.e. one compile job per core (nixpkgs hands
`make`/`ninja` `-j$NIX_BUILD_CORES` = every core). That silently assumes each
compile fits in roughly a gigabyte, which holds for almost everything — but a few
packages are far heavier. `foundationdb` is the worst offender seen so far: its
Flow actor compiler expands each source file into an enormous single translation
unit, and with `-O3` (plus `-DUSE_LTO=ON` on Linux) a single `cc1plus` peaks at
3–4 GiB. One job per core then asks for several times the RAM the machine has, and
the result is OOM-killed compilers on Linux (`g++: fatal error: Killed signal
terminated program cc1plus`, visible in `dmesg` as `Out of memory: Killed process
… (cc1plus)`) and a thrashing, glacially slow build on macOS (the memory
compressor swaps instead of killing, so it survives but crawls).

The scarce resource is **RAM per core**, not total RAM or total cores — and all
three builders are high-core / modest-RAM boxes, the worst shape for this:

| builder         | system        | RAM    | cores | RAM/core |
| --------------- | ------------- | ------ | ----- | -------- |
| `ubuntu`        | aarch64-linux | 31 GiB | 18    | 1.7 GiB  |
| `sandbox-amd64` | x86_64-linux  | 60 GiB | 32    | 1.9 GiB  |
| `tahoe-vanilla` | aarch64-darwin | 16 GiB | 18   | 0.9 GiB  |

Cap `cores` on each builder to about `RAM ÷ 4 GiB`, leaving headroom for the OS
(and, on Linux, the serial LTO link step). The value lives in each machine's own
`nix.conf`, so it belongs on the machine, not in the `npd` invocation (which has
no flag to forward it):

```sh
# ubuntu (aarch64-linux, 31 GiB)
echo 'cores = 6'  | sudo tee -a /etc/nix/nix.conf

# sandbox-amd64 (x86_64-linux, 60 GiB)
ssh sandbox-amd64 "echo 'cores = 12' | sudo tee -a /etc/nix/nix.conf"

# tahoe-vanilla (aarch64-darwin, 16 GiB) — /etc/nix/nix.conf is
# Determinate-managed, so append to the user include it already sources
ssh tahoe-vanilla "echo 'cores = 3' | sudo tee -a /etc/nix/nix.custom.conf"
```

Because the builders above are `ssh://` (legacy `nix-store --serve`, not
`ssh-ng://`), the coordinator does **not** forward its own `cores` to them — each
build uses the remote machine's value — and a fresh serve process per SSH
connection re-reads `nix.conf`, so no daemon restart is needed; the coordinator's
local `aarch64-linux` builds pick it up from its own `nix.conf` the same way.
Verify:

```sh
nix show-config | grep '^cores'
ssh sandbox-amd64 nix show-config | grep '^cores'
ssh tahoe-vanilla nix show-config | grep '^cores'
```

`cores` bounds parallelism **within** one derivation; the `max-jobs` field in
`/etc/nix/machines` bounds how many derivations run on a builder at once. Peak
memory is roughly `max-jobs × cores × per-job`, so keep both modest on the 16 GiB
macOS box. This cap is coarse — it throttles every build, not just the hungry
ones — but a machine-wide `cores` value is the only place a *machine's* RAM/core
limit can be expressed today; see the note below on where a per-package or
memory-aware fix would truly belong.

### AppArmor user namespaces (Ubuntu builders)

Ubuntu 23.10+ blocks unprivileged user namespaces by default
(`kernel.apparmor_restrict_unprivileged_userns = 1`). Builds that create nested
user namespaces — notably nix's and lix's own functional test suites — then fail:
`unshare --user --map-root-user true` reports `Operation not permitted`, and e.g.
lix's `installcheck` suite goes from `Fail: 0` to `Fail: 14`. Because the failure
depends on the host's LSM policy rather than the derivation, it's effectively an
impurity, and it shows up as a spurious build failure on these VMs while the same
derivation builds fine on Hydra.

NixOS and macOS are unaffected; the two Ubuntu VMs (`ubuntu` and `sandbox-amd64`)
need the restriction disabled persistently:

```sh
echo 'kernel.apparmor_restrict_unprivileged_userns = 0' | sudo tee /etc/sysctl.d/99-nix-userns.conf
sudo sysctl --system
```

Verify with `unshare --user --map-root-user echo ok`.

### Known wart: shared `/tmp` on the macOS builder

`tahoe-vanilla` runs with `sandbox = false`, so builds share the host's real
`/tmp`. Tests that hardcode `/tmp` paths can then collide across builds: a
directory created by one `_nixbld` user persists and blocks a later build running
as a different `_nixbld` user (`PermissionError`). The concrete case seen so far
is nixpkgs' `nixos-rebuild-ng` `test_make_tmpdir`, which uses `/tmp/not-too-long`
and `/tmp/long…`. Clear the leftovers to unblock:

```sh
ssh tahoe-vanilla 'sudo rm -rf /tmp/not-too-long /tmp/long*'
```

The real fix is upstream (the test shouldn't hardcode shared `/tmp` paths); this
is unrelated to whatever change triggered the rebuild.

### Where the parallelism fix really belongs

The per-machine `cores` cap above is the right place for a *machine's* RAM/core
limit, but it's coarse: it throttles every build, not the handful that actually
overcommit memory. A complete fix needs two facts that live in two different
places — a package's peak memory per compile job, and a machine's RAM per core —
and no layer combines them today:

- **Per package, in nixpkgs.** A known-heavy derivation can pin its own compile
  parallelism regardless of the builder, which spares every downstream user
  (especially low-RAM CI) rather than just this tailnet. The established idiom is
  `env.NIX_BUILD_CORES = <n>;` — e.g. `pkgs/applications/emulators/libretro/cores/mame2015.nix`
  sets `8` for exactly this reason. A conservative cap on
  [`foundationdb`](https://github.com/NixOS/nixpkgs/blob/master/pkgs/by-name/fo/foundationdb/package.nix)
  would prevent the OOM class while being invisible on Hydra's high-RAM builders
  (the serial LTO link dominates its wall-clock anyway). The still-cleaner version
  is an upstream CMake compile job pool (`CMAKE_JOB_POOL_COMPILE`), but the
  one-line nixpkgs cap is the lowest-friction PR.
- **In Nix itself.** Both `cores` and `max-jobs` are memory-blind — the scheduler
  treats every job as equal cost. The only quantitative-ish hook that exists,
  `requiredSystemFeatures = [ "big-parallel" ]`, is a boolean opt-in, not a memory
  budget. The truly general fix is memory-aware scheduling: let a derivation
  declare an expected footprint and have Nix bound concurrency by available RAM.
  That's a long-standing gap, and it's where an everyone-benefits fix ultimately
  lives.

Until then: the machine-wide `cores` cap here is the pragmatic floor, and a
package-level `env.NIX_BUILD_CORES` in nixpkgs is the highest-leverage thing to
upstream.

[flakes]: https://wiki.nixos.org/wiki/Flakes#Other_Distros,_without_Home-Manager
