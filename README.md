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

## Docker ([x86](docker-x86) and [ARM](docker-arm))

This repo also contains dedicated Home Manager configs for use in an Ubuntu Docker container; for instance:

```sh
docker build . -t agent
docker create agent sleep infinity
```

Then in VS Code, start the container and [attach to it](https://code.visualstudio.com/docs/devcontainers/attach-container).

## [libvirt](docker-x86)

The Docker configs can also be used for virtual machines. First make sure you have [virt-manager](https://virt-manager.org/), virt-viewer, and the [libvirt NSS module](https://libvirt.org/nss.html) installed, as they are in this repo's NixOS config. Then make sure you've started the `default` network:

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

## [Lima](docker-arm)

Similarly, the ARM Linux config can be used for a Linux virtual machine on macOS, via [Lima](https://lima-vm.io/) which comes with the host-side macOS config in this repo. First create the VM:

- The username and home directory location must be set to match what this Home Manager config expects.
- Lima mounts the host-side home directory to the same path in the VM by default, so we disable that for security purposes.

```sh
limactl start --name sandbox-arm64 --cpus 18 --memory 32 --disk 2000 --set '.user.name = "agent-arm64" | .user.home = "/home/agent-arm64" | .mounts = []' template:ubuntu
```

Then configure it to start automatically in the background:

```sh
limactl start-at-login sandbox-arm64
```

Enable Lima's SSH setup:

```sh
echo 'Include ~/.lima/*/ssh.config' >> ~/.ssh/config
```

Then SSH into the new VM:

```sh
ssh lima-sandbox-arm64
```

Install Nix:

```sh
sh <(curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install) --daemon
```

Clone this repo:

```sh
git clone https://github.com/samestep/env.git ~/github/samestep/env
```

Make a symlink for Home Manager:

```sh
ln -fsT ~/github/samestep/env ~/.config/home-manager
```

And activate the config:

```sh
nix run ~/github/samestep/env#home-manager -- switch -b backup
```

## [Tart](tart)

This config can be used for macOS VMs created with [Tart](https://tart.run/), which comes with the host-side macOS config in this repo. First, download a macOS image:

```sh
tart clone ghcr.io/cirruslabs/macos-tahoe-vanilla:latest tahoe-vanilla
```

By default, Tart doesn't give the VM all CPU cores, and only gives 8 GiB of RAM and 50 GB of disk space, so adjust those as appropriate:

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

Leave that running and, in a different terminal, give the VM your public SSH key give the VM your public SSH key so you don't need to type the password each time you connect:

```sh
ssh-copy-id admin@$(tart ip tahoe-vanilla)
```

While adding the SSH key, you will need to type the password, which is `admin`. Then SSH into the VM:

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

## Tailscale

The three VMs above (`sandbox-amd64`, `sandbox-arm64`, `tahoe-vanilla`) span two physical machines, and each sits behind its host's NAT, so there's no flat network on which one can reach another directly. [Tailscale](https://tailscale.com/) fixes this: it's a mesh VPN that does NAT traversal automatically, giving every VM a stable [MagicDNS](https://tailscale.com/kb/1081/magicdns/) name reachable from the others regardless of which host it runs on. With [Tailscale SSH](https://tailscale.com/kb/1193/tailscale-ssh/) enabled, any VM can `ssh` into any other with no key management, so a coding agent on any one of them can build and test across all three platforms (`x86_64-linux`, `aarch64-linux`, `aarch64-darwin`). The network mesh is symmetric — any VM is reachable from any other — but in this setup the two Linux VMs act as controllers while the macOS VM is only reachable, not a controller (see its section below for why).

The SSH host aliases (`sandbox-amd64`, `sandbox-arm64`, `tahoe-vanilla`, each with the right username) live in [`ssh/config`](ssh/config), symlinked into place for the three agent VMs by [`modules/yolo.nix`](modules/yolo.nix). That file pins each alias to the VM's full MagicDNS name, but the tailnet's MagicDNS suffix is tailnet-specific (and this repo is public), so it isn't committed: `ssh/config` instead includes `~/.ssh/tailnet`, generated locally by the `tailnet` command (see [SSH between the VMs](#ssh-between-the-vms)). The `tailscaled` daemon has to run as root, which standalone Home Manager can't manage, so it's installed out-of-band per OS as below.

### Account

Signing in puts each VM into one Tailscale [tailnet](https://tailscale.com/kb/1136/tailnet/). Since these are autonomous agent VMs and a tailnet's default [ACL](https://tailscale.com/kb/1018/acls/) lets every device reach every other, consider giving them a dedicated Tailscale account (a separate, isolated tailnet) rather than your personal one — unless you specifically want to drive the VMs from your own machines too, in which case use one tailnet and tighten the ACL.

### Linux VMs (`sandbox-amd64`, `sandbox-arm64`)

Install Tailscale via its official installer, which sets up and enables the `tailscaled` systemd service plus a matching CLI:

```sh
curl -fsSL https://tailscale.com/install.sh | sh
```

Then bring the VM onto the tailnet with Tailscale SSH enabled (use the VM's own name):

```sh
sudo tailscale up --ssh --hostname=sandbox-amd64
```

### macOS VM (`tahoe-vanilla`)

Tailscale SSH's server only works on macOS with the open-source `tailscaled` variant, not the Mac App Store or standard GUI build — and that open-source variant is exactly the `tailscale` package this repo's config installs (see [`tart/home-manager/home.nix`](tart/home-manager/home.nix)). Register it as a launchd system daemon (the full path is needed because `sudo` doesn't inherit the Nix profile on `PATH`):

```sh
sudo "$(command -v tailscaled)" install-system-daemon
```

That copies the binary to `/usr/local/bin` and installs `/Library/LaunchDaemons/com.tailscale.tailscaled.plist`; since it's a copy, re-run it after a Home Manager upgrade to pick up a new Tailscale version. Then:

```sh
sudo tailscale up --ssh --hostname=tahoe-vanilla
```

One caveat with this variant: it doesn't point the system resolver at Tailscale's MagicDNS, so this VM can't resolve the other VMs' names. That's left as-is on purpose — this VM only needs to be *reachable from* the Linux VMs (which works regardless of DNS), not to drive them. So don't run the `tailnet` step below on it, and the `ssh <alias>` shortcuts won't work *from* here (you could still reach the others by Tailscale IP in a pinch). Making it a controller too would mean routing the tailnet's MagicDNS suffix to `100.100.100.100` via an [`/etc/resolver`](https://www.manpagez.com/man/5/resolver/) file and restarting `mDNSResponder`, which is omitted here.

### SSH between the VMs

Tailscale SSH needs an explicit policy rule even though the default ACL is allow-all. To let any of your devices SSH into any other as its non-root login user, set the `ssh` block of your [policy file](https://login.tailscale.com/admin/acls) to:

```json
"ssh": [
  {
    "action": "accept",
    "src": ["autogroup:member"],
    "dst": ["autogroup:self"],
    "users": ["autogroup:nonroot"]
  }
]
```

Use `"action": "accept"`, not the default `"check"`, which forces a periodic browser re-auth that would block an unattended agent.

Then, on each Linux VM, generate the `~/.ssh/tailnet` include that [`ssh/config`](ssh/config) expects — `tailnet` ([`bin/tailnet.py`](bin/tailnet.py)) fills in this tailnet's MagicDNS suffix from `tailscale status`:

```sh
tailnet
```

Once that's in place, from either Linux VM:

```sh
ssh sandbox-amd64   # x86_64-linux
ssh sandbox-arm64   # aarch64-linux
ssh tahoe-vanilla   # aarch64-darwin
```

[flakes]: https://wiki.nixos.org/wiki/Flakes#Other_Distros,_without_Home-Manager
