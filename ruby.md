# Ruby Gems

It's [not recommended][jekyll] to install Ruby Gems as root, so change the gem
installation path to `~/gems`:
```
$ echo 'export GEM_HOME="$HOME/gems"' >> ~/.bashrc
```
Then add these gems to the `PATH`:
```
$ echo 'export PATH="$HOME/gems/bin:$PATH"' >> ~/.bashrc
```
Then, to load those new settings into the current terminal:
```
$ source ~/.bashrc
```

[jekyll]: https://jekyllrb.com/docs/installation/ubuntu/
