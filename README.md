# env

My Ubuntu 20.04 environment.

## Installing Git

Bootstrap with an outdated version, then get the latest from a PPA, below:
```
$ sudo apt install git
```

## Cloning with SSH

Follow the [instructions on GitHub Help][ssh generate]. First, generate a new
key:
```
$ ssh-keygen -t ed25519 -C "sam@samestep.com"
```
Press enter once to use the default location, then choose a passphrase and enter
it twice. After generating, you'll want to add it to the ssh-agent; first make
sure the agent is started:
```
$ eval `ssh-agent -s`
```
Then add it to the agent:
```
$ ssh-add ~/.ssh/id_ed25519
```
Next, to [add it to GitHub][ssh github], first copy the public key to your
clipboard:
```
$ cat ~/.ssh/id_ed25519.pub
```
Then [add a new SSH key in your GitHub settings][ssh new] by choosing a
descriptive title, pasting the contents of that public key file, and clicking
"Add SSH key". If you're using WSL 2, you'll also want to [make it not
repeatedly prompt for your SSH passphrase][ssh wsl]:
```
$ echo 'eval `keychain --quiet --eval --agents ssh id_rsa`' >> ~/.bashrc
```
You can now clone this repo:
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

## Path

Most of the below setup instructions don't require modification of the path, and
for most of those that do, the modification is explicitly stated. However, a
couple (specifically [Flit](#flit) and the [Powerline shell
prompt](#powerline-shell-prompt)) share some common path configuration, so it is
consolidated here rather than being presented for both separately:
```
$ echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
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
If you're using WSL, you'll also need to [install Docker on the Windows
side][docker wsl]. Finally, verify that it worked:
```
$ docker run hello-world
```

### Flit

Install [from conda-forge][flit]:
```
$ conda install -c conda-forge flit
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
$ sdk install gradle 6.8
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

### Miniconda

Follow the [instructions on the website][miniconda], so first download the
installer:
```
$ wget -P /tmp https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh
```
Then run it:
```
$ bash /tmp/Miniconda3-latest-Linux-x86_64.sh
```
Follow the instructions, answering "yes" to all prompts that ask for a yes/no
answer.

### Node.js

First [install nvm][nvm]:
```
$ curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.37.2/install.sh | bash
```
Then install Node:
```
$ nvm install node
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
To make it work with the Ubuntu terminal, download [more fonts][powerline
fonts]:
```
$ git clone git@github.com:powerline/fonts.git ~/github/powerline/fonts
```
And install:
```
$ ~/github/powerline/fonts/install.sh
```
You'll need to configure your terminal to use the "Meslo LG S for Powerline
Regular" font. Lastly, to [make it work with VS Code][powerline-shell vs code],
download yet another font:
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
[docker wsl]: https://docs.docker.com/docker-for-windows/wsl/
[flit]: https://anaconda.org/conda-forge/flit
[gradle]: https://gradle.org/install/#with-a-package-manager
[jekyll]: https://jekyllrb.com/docs/installation/ubuntu/
[lean]: https://leanprover-community.github.io/install/debian_details.html
[leiningen]: https://purelyfunctional.tv/guide/how-to-install-clojure/#mac-leiningen
[menlo powerline]: https://github.com/abertsch/Menlo-for-Powerline#linux
[miniconda]: https://docs.conda.io/projects/conda/en/latest/user-guide/install/linux.html
[nvm]: https://github.com/nvm-sh/nvm#install--update-script
[powerline fonts]: https://github.com/powerline/fonts#installation
[powerline-shell bash]: https://github.com/b-ryan/powerline-shell#bash
[powerline-shell setup]: https://github.com/b-ryan/powerline-shell#setup
[powerline-shell vs code]: https://dev.to/mattstratton/making-powerline-work-in-visual-studio-code-terminal-1m7
[quick]: https://www.tug.org/texlive/quickinstall.html
[rust]: https://www.rust-lang.org/learn/get-started
[sdkman]: https://sdkman.io/
[settings sync]: https://code.visualstudio.com/docs/editor/settings-sync#_turning-on-settings-sync
[ssh generate]: https://help.github.com/en/github/authenticating-to-github/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent
[ssh github]: https://help.github.com/en/github/authenticating-to-github/adding-a-new-ssh-key-to-your-github-account
[ssh new]: https://github.com/settings/ssh/new
[ssh wsl]: https://stackoverflow.com/a/63803879/5044950
[stack]: https://docs.haskellstack.org/en/stable/README/
[tug]: https://www.tug.org/texlive/acquire-netinstall.html
[yarn]: https://classic.yarnpkg.com/en/docs/install#debian-stable
[yarn link]: https://classic.yarnpkg.com/en/docs/cli/link/
[zotero]: https://askubuntu.com/a/1160369/423065
[zulip]: https://zulipchat.com/help/desktop-app-install-guide
