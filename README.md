# env [![Build](https://github.com/samestep/env/actions/workflows/build.yml/badge.svg)](https://github.com/samestep/env/actions/workflows/build.yml) [![Update](https://github.com/samestep/env/actions/workflows/update.yml/badge.svg)](https://github.com/samestep/env/actions/workflows/update.yml)

My [Nix](https://nixos.org/) environment. Once you have Nix installed, the first step is to clone this repo:

```sh
nix-shell -p git gh --run "gh auth login && gh repo clone samestep/env ~/github/samestep/env"
```

There are separate configurations for the three different machines I use.

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

This machine has an Apple M1 chip and runs macOS.

[Enable flakes][flakes] by making sure this line is present in `/etc/nix/nix.conf`:

```
experimental-features = nix-command flakes
```

Then run these commands to setup the Home Manager configuration:

```sh
nix run ~/github/samestep/env#home-manager switch
rm -r ~/.config/home-manager
ln -s ~/github/samestep/env ~/.config/home-manager
nix run ~/github/samestep/env#home-manager switch
```

## [Ubuntu](ubuntu)

This machine has an x86 CPU and an NVIDIA GPU, and runs Ubuntu.

[Enable flakes][flakes] by making sure this line is present in `/etc/nix/nix.conf`:

```
experimental-features = nix-command flakes
```

Next [enable user namespace creation](https://askubuntu.com/a/1511983) by making sure the line `kernel.apparmor_restrict_unprivileged_userns = 0` is present in some file under `/etc/sysctl.d/`, e.g. by running this command:

```
echo 'kernel.apparmor_restrict_unprivileged_userns = 0' | sudo tee /etc/sysctl.d/20-apparmor-donotrestrict.conf
```

Then run these commands to setup the Home Manager configuration:

```sh
ln -fsT ~/github/samestep/env ~/.config/home-manager
nix run ~/github/samestep/env#home-manager -- switch --impure
```

## Docker ([x86](docker-x86) and [ARM](docker-arm))

This repo also contains dedicated Home Manager configs for use in an Ubuntu Docker container; for instance:

```sh
docker build . -t agent
docker create agent sleep infinity
```

Then in VS Code, start the container and [attach to it](https://code.visualstudio.com/docs/devcontainers/attach-container).

## [libvirt](docker-x86)

The Docker configs can also be used for virtual machines. First make sure you have [virt-manager](https://virt-manager.org/) and virt-viewer installed, as they are in this repo's NixOS config. Then make sure you've started the `default` network:

```sh
virsh -c qemu:///system net-start default
```

You can also run this command so the `default` network starts automatically in the future:

```sh
virsh -c qemu:///system net-autostart default
```

Download an OS ISO like [Ubuntu 26.04](https://releases.ubuntu.com/26.04/) and run this command to create a VM, tweaking the CPU/RAM/disk parameters as appropriate:

```sh
virt-install --connect qemu:///system --vcpus 32 --memory 65536 --disk size=1000 --network network=default --cdrom ubuntu-26.04-live-server-amd64.iso
```

The NixOS config in this repo includes the [osinfo-db entry for Ubuntu 26.04](https://gitlab.com/libosinfo/osinfo-db/-/commit/6f01a968803a30c7e5da631b0205c5982b20b842), so `virt-install` should identify this ISO and choose modern Ubuntu defaults.

Here's what the other flags mean:

- the `--connect` setting makes the `default` network visible
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

After rebooting, log in and take note of the IP address, which should look something like this:

```
IPv4 address for enp1s0: 192.168.122.133
```

Now you can close the virt-viewer window; you won't need it again. Reconnect using SSH:

```sh
ssh agent-amd64@192.168.122.133
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

## aarch64 Linux VM on x86 NixOS

You can also create an `aarch64-linux` VM on the x86 NixOS machine from an ARM64 installer ISO. This still uses QEMU system emulation, so it does not require ARM hardware. It is slower than a native VM, but it gives you a real `aarch64` kernel and userspace.

This repo's NixOS config installs ARM64 OVMF/AAVMF firmware, exposes it under `/etc/aarch64-linux`, and configures libvirt to use `qemu_full`. The firmware lets the emulated ARM machine boot installer ISOs through UEFI, and `qemu_full` gives libvirt access to `qemu-system-aarch64`. Rebuild first:

```sh
sudo nixos-rebuild switch
```

Make sure the libvirt `default` network is running:

```sh
virsh -c qemu:///system net-start default
virsh -c qemu:///system net-autostart default
```

Download an ARM64 installer ISO. For example, Ubuntu 26.04 publishes the ARM64 live-server ISO under `cdimage.ubuntu.com`, rather than under the AMD64-focused `releases.ubuntu.com` page:

```sh
sudo mkdir -p /var/lib/aarch64-linux
sudo chown "$USER" /var/lib/aarch64-linux
cd /var/lib/aarch64-linux

curl -LO https://cdimage.ubuntu.com/releases/26.04/release/ubuntu-26.04-live-server-arm64.iso
```

Set the ARM64 UEFI firmware paths:

```sh
FIRMWARE_CODE=/etc/aarch64-linux/AAVMF_CODE.fd
FIRMWARE_VARS_TEMPLATE=/etc/aarch64-linux/AAVMF_VARS.fd
test -e "$FIRMWARE_CODE"
test -e "$FIRMWARE_VARS_TEMPLATE"
```

Then create the VM with 8 vCPUs, 16 GiB RAM, a 250 GB disk, the ARM64 UEFI firmware, virtio disk/network devices, and libvirt's NAT network:

```sh
virt-install \
  --connect qemu:///system \
  --name aarch64-linux \
  --arch aarch64 \
  --machine virt \
  --virt-type qemu \
  --cpu cortex-a72 \
  --vcpus 8 \
  --memory 16384 \
  --disk size=250,format=qcow2,bus=virtio \
  --network network=default,model=virtio \
  --boot loader="$FIRMWARE_CODE",loader.readonly=yes,loader.type=pflash,nvram.template="$FIRMWARE_VARS_TEMPLATE" \
  --cdrom /var/lib/aarch64-linux/ubuntu-26.04-live-server-arm64.iso \
  --autostart
```

Here's why the extra flags are there:

- `--connect qemu:///system` uses the system libvirt daemon. Without it, `virt-install` may use a per-user session connection instead, where the system `default` NAT network and the VMs managed by the rest of this README are not necessarily visible.
- `--name aarch64-linux` is the persistent libvirt domain name. Without it, `virt-install` has no stable domain name to define, and the later `virsh` commands would not have a VM to refer to.
- `--arch aarch64` is the guest architecture selector. `virt-install` does not infer this from `--cpu cortex-a72`; if you omit it on an `x86_64` host, it starts from the host architecture. With `--machine virt` still present, that fails because the ARM `virt` board is not an `x86_64` machine type. If both `--arch` and `--machine` were omitted, you would be asking for an `x86_64` VM, not an ARM64 VM.
- `--machine virt` selects QEMU's generic ARM virtual board. On current libvirt/QEMU versions this is often the default once `--arch aarch64` is set, but keeping it explicit matters because ARM QEMU machine types are board models rather than the PC-style default used for `x86_64`. If another default were selected, the firmware, PCI layout, and virtio devices used below might not match.
- `--virt-type qemu` makes the emulation backend explicit. KVM can accelerate a VM only when the guest architecture matches what the host CPU can run, so an `x86_64` host cannot KVM-accelerate an `aarch64` guest. Current libvirt versions usually choose `qemu` automatically once `--arch aarch64` is set on an `x86_64` host, but spelling it out documents that this VM is emulated rather than KVM-accelerated.
- `--cpu cortex-a72` chooses a common 64-bit ARMv8 CPU model implemented by QEMU, but it does not choose the guest architecture. Without it, libvirt/QEMU may pick a version-dependent ARM CPU default. The VM may still boot, but the guest CPU features become less explicit and less reproducible.
- `--vcpus 8` and `--memory 16384` are the requested resources. If omitted, `virt-install` uses much smaller defaults, so the VM would still be ARM64 but would not have the 8 vCPUs and 16 GiB RAM intended here. The memory value is in MiB.
- `--disk size=250,format=qcow2,bus=virtio` creates the main 250 GB disk. The `format=qcow2` part is not ARM-specific; it makes the disk format explicit instead of relying on the storage-pool default, and this setup works on current libvirt even if it is omitted. The `bus=virtio` part is more important for this ARM VM: without an explicit bus, libvirt can choose a different device model, such as a USB disk, which is slower and changes the installed system's disk device. Virtio is the normal paravirtual disk interface for modern Linux guests.
- `--network network=default,model=virtio` connects the VM to libvirt's NAT network and asks for a virtio NIC. `model=virtio` is independent of the disk's `bus=virtio`; one can be virtio while the other is not. They do not need to "match", but using virtio for both avoids slower emulated devices and gives the guest predictable Linux-supported hardware. Without `network=default`, the VM may have no network; without `model=virtio`, libvirt may omit an explicit NIC model and leave the final emulated device up to defaults.
- `--boot loader="$FIRMWARE_CODE",...,nvram.template="$FIRMWARE_VARS_TEMPLATE"` gives the ARM VM UEFI firmware. The `loader` file is the executable AAVMF firmware code. The `nvram.template` file is copied into a per-VM writable UEFI variable store, where the firmware keeps boot entries and boot order. The two files can be the same size because they are both flash images, but they contain different data. Without the loader, the VM has no ARM UEFI firmware to run the installer in the normal ISO-boot path. Without the NVRAM template, the VM may not get a persistent writable variable store, so installed boot entries can fail to survive reboot.
- `loader.readonly=yes` says the firmware code image is immutable. This matters on NixOS because the firmware file lives in the read-only Nix store and because UEFI variables belong in the separate NVRAM file, not in the firmware code image. Current libvirt accepts the XML without this flag, but then the domain no longer records the intended split between read-only firmware code and writable NVRAM as clearly.
- `loader.type=pflash` says the firmware is exposed as persistent flash memory, which is how AAVMF/OVMF-style UEFI firmware is provided to QEMU guests. This one is not just cosmetic: without it, libvirt emits a loader with no pflash type, and this setup fails because ACPI on `aarch64` requires UEFI.
- `--cdrom /var/lib/aarch64-linux/ubuntu-26.04-live-server-arm64.iso` attaches the ARM64 installer ISO. Without it, the new empty disk has nothing bootable on it.
- `--autostart` is not the same thing as libvirt's save/restore behavior during host shutdown. Save/restore handles a VM that was already running when the host went down. Autostart means libvirt should start this persistent VM when the host boots. Without it, the VM can remain shut off after a host boot if there was no managed-save state to restore, or if it had been shut down before the reboot.

Install the OS normally. Use these values if you want the VM to match the rest of this repo:

- Your name: `Agent`
- Your server's name: `sandbox-arm64`
- Pick a username: `agent-arm64`
- Choose a password: `password`
- Confirm your password: `password`

Enable OpenSSH server during installation. Once installation is finished, the VM may shut off or reboot. If it is shut off, start it again. If it reboots back into the installer, eject the ISO and reboot:

```sh
virsh -c qemu:///system start aarch64-linux || true
virsh -c qemu:///system change-media aarch64-linux sda --eject || true
virsh -c qemu:///system reboot aarch64-linux || true
```

Find the VM's IP address:

```sh
virsh -c qemu:///system domifaddr aarch64-linux
virsh -c qemu:///system net-dhcp-leases default
```

Now connect over SSH, replacing the IP address with the address shown by libvirt or on the VM console:

```sh
ssh agent-arm64@192.168.122.123
```

The only reason for choosing a password at all was because installers usually require one. First enable passwordless `sudo`, then add your SSH key:

```sh
echo "agent-arm64 ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/agent && sudo chmod 0440 /etc/sudoers.d/agent
mkdir -p ~/.ssh
curl https://github.com/samestep.keys >> ~/.ssh/authorized_keys
chmod 700 ~/.ssh
chmod 600 ~/.ssh/authorized_keys
```

Inside the VM, check that it is really ARM64 and that the requested resources are visible:

```sh
uname -m
free -h
lsblk
df -h /
```

Manage the VM with:

```sh
virsh -c qemu:///system list --all
virsh -c qemu:///system shutdown aarch64-linux
virsh -c qemu:///system start aarch64-linux
virsh -c qemu:///system autostart aarch64-linux
```

## [Tart](tart)

This config can be used for macOS VMs created with [Tart](https://tart.run/), which comes with the host-side macOS config in this repo. First, download a macOS image:

```sh
tart clone ghcr.io/cirruslabs/macos-tahoe-vanilla:latest tahoe-vanilla
```

By default, Tart gives the VM only 50 GB of disk space and access to half the CPU cores, so adjust those as appropriate:

```sh
tart set tahoe-vanilla --cpu 8 --disk-size 250
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

That should pop up a dialogue which you need to accept. Now shut down the VM again and reboot it once more, this time without graphics:

```sh
tart run --no-graphics tahoe-vanilla
```

Leave that running and SSH into the VM from a different terminal:

```sh
ssh admin@$(tart ip tahoe-vanilla)
```

The password is `admin`. [Install Nix](https://github.com/DeterminateSystems/nix-installer/tree/v3.20.0#install-determinate-nix):

```sh
curl -fsSL https://install.determinate.systems/nix | sh -s -- install
```

You may need to start a new shell. Clone this repo:

```sh
git clone https://github.com/samestep/env.git ~/github/samestep/env
```

Set up the Home Manager symlink:

```sh
ln -s ~/github/samestep/env ~/.config/home-manager
```

And finally activate the Home Manager config:

```sh
nix run ~/github/samestep/env#home-manager switch
```

[flakes]: https://wiki.nixos.org/wiki/Flakes#Other_Distros,_without_Home-Manager
