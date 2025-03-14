# env

My [Nix](https://nixos.org/) environment. Once you have Nix installed, the first step is to clone this repo and set up the Nixpkgs config which is needed for bootstrapping:

```sh
mkdir -p ~/github/samestep
cd ~/github/samestep
nix-shell -p git gh --run "gh auth login && gh repo clone samestep/env"
ln -fs ~/github/samestep/env/nixpkgs ~/.config
```

There are separate configurations for the two different machines I use.

## [Desktop](desktop)

This machine has an x86 CPU and an NVIDIA GTX 970, runs NixOS, and follows the Nixpkgs version 24.11 channel.

Run these commands to setup the NixOS configuration:

```sh
sudo ln -fs ~/github/samestep/env/nixos/configuration.nix /etc/nixos/configuration.nix
nixos-rebuild switch --use-remote-sudo
```

Run these commands to do a [standalone installation of Home Manager][home-manager standalone] and setup the Home Manager configuration:

```sh
ln -fs ~/github/samestep/env/desktop/home-manager ~/.config
nix-channel --add https://github.com/nix-community/home-manager/archive/release-24.11.tar.gz home-manager
nix-channel --update
nix-shell '<home-manager>' -A install
```

You may need to log out and back in to see everything installed in the GNOME applications launcher.

## [MacBook](macbook)

This machine has an Apple M1 chip, runs macOS, and follows the Nixpkgs version 25.05 channel.

Run these commands to do a [standalone installation of Home Manager][home-manager standalone] and setup the Home Manager configuration:

```sh
ln -fs ~/github/samestep/env/macbook/home-manager ~/.config
nix-channel --add https://github.com/nix-community/home-manager/archive/master.tar.gz home-manager
nix-channel --update
nix-shell '<home-manager>' -A install
```

[home-manager standalone]: https://nix-community.github.io/home-manager/index.xhtml#sec-install-standalone
