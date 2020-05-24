# env

My Ubuntu environment. Initial setup:

```sh
sudo apt install git
git clone https://github.com/samestep/env.git
cd env
./once.sh
./env.sh
```

[Apparently][parent directory question], getting the parent directory of a shell
script is hard, so all the scripts in this repository assume that they will be
run from the repository root.

You can also use `./env.py` to generate the following files:

- `ppas.json`, a list of installed PPA's
- `apt_packages.json`, a list of manually-installed APT packages
- `snaps.json`, a list of installed snaps

Then you can act on any differences between generated versions and the ones
already present in this repository, to synchronize in either direction.

[parent directory question]: https://stackoverflow.com/q/59895/5044950
