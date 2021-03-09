# TeX Live

To install TeX Live, first download the [`.tar.gz` file from the TeX Users
Group][tug]:
```
$ wget -P /tmp http://mirror.ctan.org/systems/texlive/tlnet/install-tl-unx.tar.gz
```
Then follow the [Quick install][quick] instructions to unpack:
```
$ tar xf /tmp/install-tl-unx.tar.gz -C /tmp
```
And run the install script:
```
$ sudo /tmp/install-tl-20*/install-tl
```
Enter `I` when prompted. After the installation finishes, put the new binaries
on your `PATH`:
```
$ echo 'export PATH="/usr/local/texlive/2020/bin/x86_64-linux:$PATH"' >> ~/.bashrc
```

[quick]: https://www.tug.org/texlive/quickinstall.html
[tug]: https://www.tug.org/texlive/acquire-netinstall.html
