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

## Git config

To make your `~/.gitconfig` a symbolic link to the `.gitconfig` in this repo:
```
$ ln -fs "$PWD/.gitconfig" ~/.gitconfig
```

## APT and Snap

To synchronize your PPA's, APT packages, and snaps with the JSON files here:
```
$ ./env.py
```

## Gradle

To install Gradle, first [install SDKMAN!][sdkman]:
```
$ curl -s "https://get.sdkman.io" | bash
```
Then follow the [package manager instructions on the Gradle website][gradle]:
```
$ sdk install gradle 6.4.1
```

[generate]: https://help.github.com/en/github/authenticating-to-github/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent#generating-a-new-ssh-key
[github]: https://help.github.com/en/github/authenticating-to-github/adding-a-new-ssh-key-to-your-github-account
[gradle]: https://gradle.org/install/#with-a-package-manager
[sdkman]: https://sdkman.io/
[ssh]: https://help.github.com/en/github/authenticating-to-github/connecting-to-github-with-ssh
