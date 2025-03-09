# NixOS config

From a fresh [NixOS installation](https://nixos.org/download/), run these commands to bootstrap the NixOS configuration:

```sh
mkdir -p ~/github/samestep/nixos-config/etc/nixos
curl https://raw.githubusercontent.com/samestep/nixos-config/refs/heads/main/etc/nixos/configuration.nix -o ~/github/samestep/nixos-config/etc/nixos/configuration.nix
sudo ln -fs ~/github/samestep/nixos-config/etc/nixos/configuration.nix /etc/nixos/configuration.nix
nixos-rebuild switch --use-remote-sudo
```

Then run these commands to bootstrap the Home Manager configuration:

```sh
mkdir -p ~/github/samestep/nixos-config/home/sam/.config/{home-manager,nixpkgs}
curl https://raw.githubusercontent.com/samestep/nixos-config/refs/heads/main/home/sam/.config/home-manager/home.nix -o ~/github/samestep/nixos-config/home/sam/.config/home-manager/home.nix
curl https://raw.githubusercontent.com/samestep/nixos-config/refs/heads/main/home/sam/.config/nixpkgs/config.nix -o ~/github/samestep/nixos-config/home/sam/.config/nixpkgs/config.nix
ln -fs ~/github/samestep/nixos-config/home/sam/.config/{home-manager,nixpkgs} ~/.config
```

Then run [these commands](https://nix-community.github.io/home-manager/index.xhtml#sec-install-standalone) to do a standalone installation of Home Manager:

```sh
nix-channel --add https://github.com/nix-community/home-manager/archive/release-24.11.tar.gz home-manager
nix-channel --update
nix-shell '<home-manager>' -A install
```

Finally, run these commands to replace the bootstrapped configuration by cloning this repository:

```sh
cd ~/github/samestep
rm -r nixos-config
gh repo clone samestep/nixos-config
home-manager switch
```

You may need to log out and back in to see everything installed in the GNOME applications launcher.
