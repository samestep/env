#!/bin/sh

sudo apt install git
git config --global core.excludesfile "$PWD/gitignore"
git config --global credential.helper "cache --timeout=3600"
git config --global push.default simple
git config --global user.email sam@samestep.com
git config --global user.name "Sam Estep"
git config --global user.signingkey 2B42037F

sudo apt install vim

sudo apt install emacs
mkdir ~/.emacs.d
ln -fs "$PWD/init.el" ~/.emacs.d/init.el

wget -O https://github.com/atom/atom/releases/download/v1.15.0/atom-amd64.deb
sudo dpkg -i atom-amd64.deb
apm install advanced-open-file@0.16.6
apm install atom-latex@0.7.2
apm install keyboard-scroll@0.7.0
apm install latextools@0.8.5
apm install platformio-ide-terminal@2.5.0
ln -fs "$PWD/config.cson" ~/.atom/config.cson
ln -fs "$PWD/keymap.cson" ~/.atom/keymap.cson
ln -fs "$PWD/snippets.cson" ~/.atom/snippets.cson

sudo apt install pandoc

sudo apt install texlive texlive-xetex latexmk

sudo apt install clang

sudo rm /etc/apt/sources.list.d/webupd8team-ubuntu-java-*
sudo add-apt-repository ppa:webupd8team/java
sudo apt update
sudo apt install oracle-java8-installer

sudo curl -o /usr/local/bin/lein https://raw.githubusercontent.com/technomancy/leiningen/stable/bin/lein
sudo chmod +x /usr/local/bin/lein
mkdir ~/.lein
ln -fs "$PWD/profiles.clj" ~/.lein/profiles.clj
lein

sudo curl -Lo /usr/local/bin/boot https://github.com/boot-clj/boot-bin/releases/download/latest/boot.sh
sudo chmod +x /usr/local/bin/boot
mkdir ~/.boot
echo BOOT_CLOJURE_VERSION=1.8.0 > ~/.boot/boot.properties
ln -fs "$PWD/profile.boot" ~/.boot/profile.boot
boot -u

curl https://sh.rustup.rs -sSf | sh
cargo install racer
rustup component add rust-src

sudo apt install nautilus-dropbox

sudo apt install keepassx

sudo apt install steam dnsmasq

sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys BBEBDCB318AD50EC6865090613B00F1FD2C19886
echo deb http://repository.spotify.com stable non-free | sudo tee /etc/apt/sources.list.d/spotify.list
sudo apt update
sudo apt install spotify-client
