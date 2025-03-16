# env

My [Nix](https://nixos.org/) environment. Once you have Nix installed, the first step is to clone this repo:

```sh
nix-shell -p git gh --run "gh auth login && gh repo clone samestep/env ~/github/samestep/env"
```

There are separate configurations for the two different machines I use.

## [Desktop](desktop)

This machine has an x86 CPU and an NVIDIA GTX 970, and runs NixOS.

Run these commands to setup the NixOS configuration:

```sh
sudo ln -fs ~/github/samestep/env/desktop/nixos/configuration.nix /etc/nixos/configuration.nix
nixos-rebuild switch --use-remote-sudo
```

Then run these commands to do a [standalone installation of Home Manager][home-manager standalone] and setup the Home Manager configuration:

```sh
ln -fsT ~/github/samestep/env ~/.config/home-manager
nix run home-manager/release-24.11 -- init --switch
```

You may need to log out and back in to see everything installed in the GNOME applications launcher.

## [MacBook](macbook)

This machine has an Apple M1 chip and runs macOS.

[Enable flakes](https://wiki.nixos.org/wiki/Flakes#Other_Distros,_without_Home-Manager) by making sure this line is present in `/etc/nix/nix.conf`:

```
experimental-features = nix-command flakes
```

Then run these commands to do a [standalone installation of Home Manager][home-manager standalone] and setup the Home Manager configuration:

```sh
ln -fs ~/github/samestep/env ~/.config/home-manager
nix run home-manager/release-24.11 -- init --switch
```

[home-manager standalone]: https://nix-community.github.io/home-manager/index.xhtml#sec-flakes-standalone
