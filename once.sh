#!/bin/sh

# asks for confirmation
sudo rm /etc/apt/sources.list.d/webupd8team-ubuntu-java-*
sudo add-apt-repository ppa:webupd8team/java
sudo apt update

# appends to file
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.profile

# presents options
curl https://sh.rustup.rs -sSf | sh
