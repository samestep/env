#!/bin/sh

sudo apt install net-tools

git config --global credential.helper "cache --timeout=3600"
git config --global push.default simple
git config --global user.email sam@samestep.com
git config --global user.name "Sam Estep"
git config --global user.signingkey 2B42037F

sudo apt install vim

sudo apt install emacs
mkdir ~/.emacs.d
ln -fs "$PWD/init.el" ~/.emacs.d/init.el

wget -N https://github.com/atom/atom/releases/download/v1.28.0/atom-amd64.deb
sudo apt install gconf2 gconf-service
sudo dpkg -i atom-amd64.deb
apm install advanced-open-file@0.16.6
apm install atlilypond@1.2.2
apm install atom-latex@0.8.4
apm install atom-typescript@12.6.2
apm install center-line@1.2.4
apm install file-types@0.5.5
apm install go-plus@5.5.2
apm install hydrogen@2.3.0
apm install ink@0.6.5
apm install keyboard-scroll@0.7.0
apm install language-gitignore@0.3.0
apm install language-idris@0.4.9
apm install language-matlab@0.2.1
apm install language-rust@0.4.10
apm install latextools@0.8.5
apm install lilycompile@0.9.1
apm install linter@2.3.0
apm install linter-eslint@8.4.1
apm install linter-htmlhint@1.6.0
apm install linter-stylelint@4.4.3
apm install linter-ui-default@1.7.1
apm install lisp-paredit@0.5.5
apm install parinfer@1.20.0
apm install platformio-ide-terminal@2.8.0
apm install proto-repl@1.4.20
apm install proto-repl-charts@0.4.1
apm install script@3.18.1
apm install set-syntax@0.3.2
apm install wordcount@2.10.4
ln -fs "$PWD/config.cson" ~/.atom/config.cson
ln -fs "$PWD/init.coffee" ~/.atom/init.coffee
ln -fs "$PWD/keymap.cson" ~/.atom/keymap.cson
ln -fs "$PWD/snippets.cson" ~/.atom/snippets.cson
ln -fs "$PWD/styles.less" ~/.atom/styles.less

sudo apt install pandoc

sudo apt install texlive-full latexmk

sudo apt install lilypond

sudo apt install clang make cmake

sudo apt install npm

curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | sudo apt-key add -
echo "deb https://dl.yarnpkg.com/debian/ stable main" | sudo tee /etc/apt/sources.list.d/yarn.list
sudo apt-get update && sudo apt-get install yarn

npm install -g typescript

sudo apt install python-pip python3-pip

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

wget -N https://storage.googleapis.com/golang/go1.8.1.linux-amd64.tar.gz
sudo tar -C /usr/local -xzf go1.8.1.linux-amd64.tar.gz

sudo apt install haskell-platform

cabal update
cabal install idris

cargo install racer
rustup component add rust-src

sudo apt install ipython
pip install jupyter
pip install octave_kernel
python -m octave_kernel.install

sudo apt install nautilus-dropbox

sudo apt install keepassx

sudo snap install slack --classic

sudo apt install steam

sudo snap install spotify

sudo apt install libqt5widgets5 libqt5network5 libqt5svg5
# http://www.styluslabs.com/download/write-tgz

sudo apt install gnome-shell-pomodoro

wget -N https://apps.ankiweb.net/downloads/current/anki-2.1.2-linux-amd64.tar.bz2
tar xjf anki-2.1.2-linux-amd64.tar.bz2
cd anki-2.1.2-linux-amd64 # watch out for this I guess
sudo make install

sudo add-apt-repository ppa:kritalime/ppa
sudo apt-get update
sudo apt-get install krita
