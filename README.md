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

## [Lima](docker-arm)

Similarly, the ARM Linux config can be used for a Linux virtual machine on macOS, via [Lima](https://lima-vm.io/) which comes with the host-side macOS config in this repo. First create the VM:

- The username and home directory location must be set to match what this Home Manager config expects.
- Lima mounts the host-side home directory to the same path in the VM by default, so we disable that for security purposes.
- By default Lima only gives the VM [user-mode networking](https://lima-vm.io/docs/config/network/user-v2/) (a userspace TCP/IP stack on the host), and SSH reaches the VM via a port forward through that stack, which adds enough per-packet latency to make interactive SSH typing lag. We add a [`vzNAT`](https://lima-vm.io/docs/config/network/vmnet/) interface so the VM also gets a real IP on Apple's `vmnet` network (the same `192.168.64.0/24` network, and mechanism, that Tart uses), reachable directly from the host. SSH straight to that IP to get the low-latency path. This requires `vmType: vz`, which is the default on Apple Silicon.

```sh
limactl start --name sandbox-arm64 --cpus 18 --memory 32 --disk 2000 --set '.user.name = "agent-arm64" | .user.home = "/home/agent-arm64" | .mounts = [] | .networks = [{"vzNAT": true}]' template:ubuntu
```

Then configure it to start automatically in the background:

```sh
limactl start-at-login sandbox-arm64
```

Then SSH into the new VM. The VM advertises itself over mDNS as `lima-sandbox-arm64.local` (Lima enables `MulticastDNS` in the guest, and the `vzNAT` interface inherits it), so you can connect directly to its `vmnet` address without hardcoding its DHCP-assigned IP. This bypasses Lima's user-mode port forward, whose per-packet latency makes interactive typing lag:

```sh
ssh -i ~/.lima/_config/user agent-arm64@lima-sandbox-arm64.local
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

As an optional followup step, install Tailscale to be able to talk to other VMs; installing via Home Manager doesn't work properly on Ubuntu, so just use the official installer:

```sh
curl -fsSL https://tailscale.com/install.sh | sh
```

Connect to the tailnet:

```sh
sudo tailscale up --ssh --hostname=sandbox-arm64
```

And run this repo's script to generate `~/.ssh/tailnet`:

```sh
tailnet
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

As an optional followup step, activate Tailscale to let other VMs connect to this one; the Home Manager config provides the open-source tailscaled variant since that's the only macOS one with an SSH server, but it still needs to be registered with launchd:

```sh
sudo "$(command -v tailscaled)" install-system-daemon
```

Connect to the tailnet:

```sh
sudo tailscale up --ssh --hostname=tahoe-vanilla
```

Note that, without additional setup, this VM can only receive Tailscale SSH connections, and cannot SSH into other VMs on the tailnet.

[flakes]: https://wiki.nixos.org/wiki/Flakes#Other_Distros,_without_Home-Manager
