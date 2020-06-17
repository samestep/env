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

### Lean

Follow the [Debian/Ubuntu instructions][lean]. The `apt` packages are already
covered, so first install `elan`:
```
$ curl https://raw.githubusercontent.com/Kha/elan/master/elan-init.sh -sSf | sh
```
The VS Code extension is covered in the VS Code section of this README. Lastly,
don't use `sudo` to install `mathlibtools` from pip:
```
$ pip3 install mathlibtools
```

### Ruby Gems

It's [not recommended][jekyll] to install Ruby Gems as root, so change the gem
installation path to `~/gems`:
```
$ echo 'export GEM_HOME="$HOME/gems"' >> ~/.bashrc
```
Then add these gems to the `PATH`:
```
$ echo 'export PATH="$HOME/gems/bin:$PATH"' >> ~/.bashrc
```
Then, to load those new settings into the current terminal:
```
$ source ~/.bashrc
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

### Zotero

This [comes from APT][zotero], but it requires some special setup:
```
$ wget -qO- https://github.com/retorquere/zotero-deb/releases/download/apt-get/install.sh | sudo bash
```
Then update the local package list:
```
$ sudo apt update
```
And install:
```
$ sudo apt install zotero
```

### Zulip

This [also comes from APT][zulip], but it also requires some special setup;
first add the keyserver:
```
$ sudo apt-key adv --keyserver pool.sks-keyservers.net --recv 69AD12704E71A4803DCA3A682424BE5AE9BD10D9
```
Then add to the list of sources:
```
$ echo "deb https://dl.bintray.com/zulip/debian/ stable main" | sudo tee -a /etc/apt/sources.list.d/zulip.list
```
Next, update the local package list:
```
$ sudo apt update
```
And install:
```
$ sudo apt install zulip
```

[generate]: https://help.github.com/en/github/authenticating-to-github/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent#generating-a-new-ssh-key
[gist]: https://gist.github.com/samestep/98f356493a7ffd14722bdea9ae4a3adf
[github]: https://help.github.com/en/github/authenticating-to-github/adding-a-new-ssh-key-to-your-github-account
[gradle]: https://gradle.org/install/#with-a-package-manager
[jekyll]: https://jekyllrb.com/docs/installation/ubuntu/
[lean]: https://leanprover-community.github.io/install/debian_details.html
[quick]: https://www.tug.org/texlive/quickinstall.html
[sdkman]: https://sdkman.io/
[settings sync]: https://marketplace.visualstudio.com/items?itemName=Shan.code-settings-sync
[ssh]: https://help.github.com/en/github/authenticating-to-github/connecting-to-github-with-ssh
[tug]: https://www.tug.org/texlive/acquire-netinstall.html
[zotero]: https://askubuntu.com/a/1160369/423065
[zulip]: https://zulipchat.com/help/desktop-app-install-guide
