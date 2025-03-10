# NixOS config

From a fresh [NixOS installation](https://nixos.org/download/), run these commands to clone this repo:

```sh
mkdir -p ~/github/samestep
cd ~/github/samestep
nix-shell -p git gh --run "gh auth login && gh repo clone samestep/nixos-config"
```

Run these commands to setup the NixOS configuration:

```sh
sudo ln -fs ~/github/samestep/nixos-config/etc/nixos/configuration.nix /etc/nixos/configuration.nix
nixos-rebuild switch --use-remote-sudo
```

Run these commands to do a [standalone installation of Home Manager](https://nix-community.github.io/home-manager/index.xhtml#sec-install-standalone) and setup the Home Manager configuration:

```sh
ln -fs ~/github/samestep/nixos-config/home/sam/.config/{home-manager,nixpkgs} ~/.config
nix-channel --add https://github.com/nix-community/home-manager/archive/release-24.11.tar.gz home-manager
nix-channel --update
nix-shell '<home-manager>' -A install
```

You may need to log out and back in to see everything installed in the GNOME applications launcher.
