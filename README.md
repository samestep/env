# env

My Ubuntu environment. To use from scratch (after setting up an [SSH key][]):

```sh
$ sudo apt install git
$ git clone git@github.com:samestep/env.git
$ cd env
$ ./env.py
```

That Python script synchronizes all things APT and Snap. Then there are a few
other scripts that you might want to use:

```sh
$ ./gitconfig.sh # links ~/.gitconfig to the .gitconfig in this repo
$ ./gradle.sh # installs Gradle
$ ./yarn.sh # installs Yarn
```

[ssh key]: https://help.github.com/en/github/authenticating-to-github/connecting-to-github-with-ssh
