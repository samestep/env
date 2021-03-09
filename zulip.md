# Zulip

This [comes from APT][install], but it requires some special setup; first add
the keyserver:
```
$ sudo apt-key adv --keyserver pool.sks-keyservers.net --recv 69AD12704E71A4803DCA3A682424BE5AE9BD10D9
```
Then add to the list of sources:
```
$ echo "deb https://dl.bintray.com/zulip/debian/ stable main" | sudo tee -a /etc/apt/sources.list.d/zulip.list
```
Next, update the local package list:
```
$ sudo apt update
```
And install:
```
$ sudo apt install zulip
```

[install]: https://zulipchat.com/help/desktop-app-install-guide
