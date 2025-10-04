# env

My [Nix](https://nixos.org/) environment. Once you have Nix installed, the first step is to clone this repo:

```sh
nix-shell -p git gh --run "gh auth login && gh repo clone samestep/env ~/github/samestep/env"
```

There are separate configurations for the three different machines I use.

## [NixOS](nixos)

This machine has an x86 CPU and an NVIDIA GTX 970, and runs NixOS.

Run these commands to setup the NixOS configuration:

```sh
sudo ln -fs ~/github/samestep/env/nixos/nixos/configuration.nix /etc/nixos/configuration.nix
nixos-rebuild switch --use-remote-sudo
```

Then run these commands to do a [standalone installation of Home Manager][home-manager standalone] and setup the Home Manager configuration:

```sh
ln -fsT ~/github/samestep/env ~/.config/home-manager
nix run ~/github/samestep/env -- init --switch
```

You may need to log out and back in to see everything installed in the GNOME applications launcher, and to let Dropbox start for the first time.

## [macOS](macos)

This machine has an Apple M1 chip and runs macOS.

[Enable flakes][flakes] by making sure this line is present in `/etc/nix/nix.conf`:

```
experimental-features = nix-command flakes
```

Then run these commands to do a [standalone installation of Home Manager][home-manager standalone] and setup the Home Manager configuration:

```sh
nix run ~/github/samestep/env -- init --switch
rm -r ~/.config/home-manager
ln -s ~/github/samestep/env ~/.config/home-manager
home-manager switch
```

Finally, run these commands to setup [nix-darwin][]:

```sh
sudo ln -s ~/github/samestep/env /etc/nix-darwin
sudo darwin-rebuild switch
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

Then run these commands to do a [standalone installation of Home Manager][home-manager standalone] and setup the Home Manager configuration:

```sh
ln -fsT ~/github/samestep/env ~/.config/home-manager
nix run ~/github/samestep/env -- init --switch --impure
```

[flakes]: https://wiki.nixos.org/wiki/Flakes#Other_Distros,_without_Home-Manager
[home-manager standalone]: https://nix-community.github.io/home-manager/index.xhtml#sec-flakes-standalone
[nix-darwin]: https://github.com/nix-darwin/nix-darwin
