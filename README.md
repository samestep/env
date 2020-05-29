# env

My Ubuntu 18.04 environment.

## Installing Git

Bootstrap with an outdated version, then get the latest from a PPA, below:
```
$ sudo apt install git
```

## Cloning with SSH

Follow the [instructions on GitHub Help][ssh]. Most likely, you just need to
[generate a new key][generate]:
```
$ ssh-keygen -t rsa -b 4096 -C "sam@samestep.com"
```
Then [add it to GitHub][github], and clone:
```
$ git clone git@github.com:samestep/env.git
```
The rest of the instructions here assume that your working directory is in your
clone of this repository:
```
$ cd env
```

## APT and Snap

To synchronize your PPA's, APT packages, and snaps with the JSON files here:
```
$ ./env.py
```

## Other

The things above need to be done more or less in the order they're given in
order to work; the things below can be done in any order.

### Git config

To make your `~/.gitconfig` a symbolic link to the `.gitconfig` in this repo:
```
$ ln -fs "$PWD/.gitconfig" ~/.gitconfig
```

### Gradle

To install Gradle, first [install SDKMAN!][sdkman]:
```
$ curl -s "https://get.sdkman.io" | bash
```
Then follow the [package manager instructions on the Gradle website][gradle]:
```
$ sdk install gradle 6.4.1
```

### TeX Live

To install TeX Live, first download the [`.tar.gz` file from the TeX Users
Group][tug]:
```
$ wget http://mirror.ctan.org/systems/texlive/tlnet/install-tl-unx.tar.gz
```
Then follow the [Quick install][quick] instructions to unpack:
```
$ tar xf install-tl-unx.tar.gz
```
Move into the unpacked folder:
```
$ cd install-tl-20*
```
And run the install script:
```
$ ./install.tl
```

### VS Code

To sync your settings with [the Gist][gist], open VS Code and follow the
["Download your Settings" instructions from the Settings Sync page][settings
sync].

[generate]: https://help.github.com/en/github/authenticating-to-github/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent#generating-a-new-ssh-key
[gist]: https://gist.github.com/samestep/98f356493a7ffd14722bdea9ae4a3adf
[github]: https://help.github.com/en/github/authenticating-to-github/adding-a-new-ssh-key-to-your-github-account
[gradle]: https://gradle.org/install/#with-a-package-manager
[quick]: https://www.tug.org/texlive/quickinstall.html
[sdkman]: https://sdkman.io/
[settings sync]: https://marketplace.visualstudio.com/items?itemName=Shan.code-settings-sync
[ssh]: https://help.github.com/en/github/authenticating-to-github/connecting-to-github-with-ssh
[tug]: https://www.tug.org/texlive/acquire-netinstall.html
