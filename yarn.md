# Yarn 1

Following the [instructions from the website][install], first add the key for
the repo:
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
Finally, to be able to easily run binaries installed via [`yarn link`][link]:
```
$ echo 'export PATH="$HOME/.yarn/bin:$PATH"' >> ~/.bashrc
```

[install]: https://classic.yarnpkg.com/en/docs/install#debian-stable
[link]: https://classic.yarnpkg.com/en/docs/cli/link/
