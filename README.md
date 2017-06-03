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

[Also][atom question], Atom screws up the formatting of `config.cson`, so this
command mostly fixes that:

```sh
./cson.cljs config.cson
```

[atom question]: https://stackoverflow.com/q/42776373/5044950
[parent directory question]: https://stackoverflow.com/q/59895/5044950
