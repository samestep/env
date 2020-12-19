# env

My Ubuntu 20.04 environment.

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

### Clojure

Use the [installation instructions from the website][clojure]. First download
the installation script:
```
$ curl -O https://download.clojure.org/install/linux-install-1.10.1.561.sh
```
Then give it the right permissions:
```
$ chmod +x linux-install-1.10.1.561.sh
```
And run it:
```
$ sudo ./linux-install-1.10.1.561.sh
```

### Docker


Follow the [official installation instructions][docker]. First update APT:
```
$ sudo apt update
```
Then install some prerequisites:
```
$ sudo apt install apt-transport-https ca-certificates curl gnupg-agent software-properties-common
```
And add the Docker GPG key:
```
$ curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
```
Check that it worked:
```
$ sudo apt-key fingerprint 0EBFCD88
```
Now add the stable repository:
```
$ sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
```
Update APT again:
```
$ sudo apt update
```
And install Docker:
```
$ sudo apt install docker-ce docker-ce-cli containerd.io
```
Next follow the [official post-installation instructions][docker post] to make
it work without `sudo`:
```
$ sudo usermod -aG docker $USER
```
Reboot:
```
$ reboot
```
And verify that it worked:
```
$ docker run hello-world
```

### Flit

Install [from conda-forge][flit]:
```
$ conda install -c conda-forge flit
```
And add its output folder to the PATH:
```
$ echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
```

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

### Haskell Stack

Follow the instructions from [the website][stack]:
```
$ wget -qO- https://get.haskellstack.org/ | sh
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

### Leiningen

Basically follow the [instructions from purelyfunctional.tv][leiningen]. First
download:
```
$ wget https://raw.githubusercontent.com/technomancy/leiningen/stable/bin/lein
```
Then make it executable:
```
$ sudo chmod +x lein
```
Then move it into `PATH`:
```
$ sudo mv lein /usr/local/bin/lein
```

### Powerline shell prompt

Follow the [general setup][powerline-shell setup]:
```
$ pip install powerline-shell
```
Then [reconfigure Bash][powerline-shell bash]:
```
$ cat powerline-shell.sh >> ~/.bashrc
```
Make a place for the config:
```
$ mkdir -p ~/.config/powerline-shell
```
And sync with the file in this repo:
```
$ ln -fs "$PWD/powerline-shell.json" ~/.config/powerline-shell/config.json
```
To [make it work with VS Code][powerline-shell vs code], download this font:
```
$ wget -P ~/.fonts https://github.com/abertsch/Menlo-for-Powerline/raw/79b9e8d/Menlo%20for%20Powerline.ttf
```
And [update the fonts cache][menlo powerline]:
```
$ fc-cache -vf ~/.fonts
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

### Rust

Run the [installation script][rust]:
```
$ curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```
Accept all the default settings.

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
$ sudo ./install-tl
```
Enter `I` when prompted. After the installation finishes, put the new binaries
on PATH:
```
$ echo 'export PATH="/usr/local/texlive/2020/bin/x86_64-linux:$PATH"' >> ~/.bashrc
```

### VS Code

To sync your settings, open VS Code and follow the ["Turn on Settings Sync"
instructions from the VS Code docs][settings sync].

### Yarn 1

Following the [instructions from the website][yarn], first add the key for the
repo:
```
$ curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -
```
Then add the repo URL to the APT config:
```
$ echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
```
And install:
```
$ sudo apt update && sudo apt install yarn
```
Finally, to be able to easily run binaries installed via [`yarn link`][yarn
link]:
```
$ echo 'export PATH="$HOME/.yarn/bin:$PATH"' >> ~/.bashrc
```


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

[clojure]: https://www.clojure.org/guides/getting_started#_installation_on_linux
[docker]: https://docs.docker.com/engine/install/ubuntu/#install-using-the-repository
[docker post]: https://docs.docker.com/engine/install/linux-postinstall/#manage-docker-as-a-non-root-user
[flit]: https://anaconda.org/conda-forge/flit
[generate]: https://help.github.com/en/github/authenticating-to-github/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent#generating-a-new-ssh-key
[github]: https://help.github.com/en/github/authenticating-to-github/adding-a-new-ssh-key-to-your-github-account
[gradle]: https://gradle.org/install/#with-a-package-manager
[jekyll]: https://jekyllrb.com/docs/installation/ubuntu/
[lean]: https://leanprover-community.github.io/install/debian_details.html
[leiningen]: https://purelyfunctional.tv/guide/how-to-install-clojure/#mac-leiningen
[menlo powerline]: https://github.com/abertsch/Menlo-for-Powerline#linux
[powerline-shell bash]: https://github.com/b-ryan/powerline-shell#bash
[powerline-shell setup]: https://github.com/b-ryan/powerline-shell#setup
[powerline-shell vs code]: https://dev.to/mattstratton/making-powerline-work-in-visual-studio-code-terminal-1m7
[quick]: https://www.tug.org/texlive/quickinstall.html
[rust]: https://www.rust-lang.org/learn/get-started
[sdkman]: https://sdkman.io/
[settings sync]: https://code.visualstudio.com/docs/editor/settings-sync#_turning-on-settings-sync
[ssh]: https://help.github.com/en/github/authenticating-to-github/connecting-to-github-with-ssh
[stack]: https://docs.haskellstack.org/en/stable/README/
[tug]: https://www.tug.org/texlive/acquire-netinstall.html
[yarn]: https://classic.yarnpkg.com/en/docs/install#debian-stable
[yarn link]: https://classic.yarnpkg.com/en/docs/cli/link/
[zotero]: https://askubuntu.com/a/1160369/423065
[zulip]: https://zulipchat.com/help/desktop-app-install-guide
