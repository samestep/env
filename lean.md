# Lean

Follow the [Debian/Ubuntu instructions][debian]. The `apt` packages are already
covered, so first install `elan`:
```
$ curl https://raw.githubusercontent.com/Kha/elan/master/elan-init.sh -sSf | sh
```
The VS Code extension is covered in the VS Code section of this README. Lastly,
don't use `sudo` to install `mathlibtools` from pip:
```
$ pip3 install mathlibtools
```

[debian]: https://leanprover-community.github.io/install/debian_details.html
