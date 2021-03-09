# SSH

Follow the [instructions on GitHub Help][generate]. First, generate a new key:
```
$ ssh-keygen -t ed25519 -C "sam@samestep.com"
```
Press enter once to use the default location, then choose a passphrase and enter
it twice. After generating, you'll want to add it to the ssh-agent; first make
sure the agent is started:
```
$ eval `ssh-agent -s`
```
Then add it to the agent:
```
$ ssh-add ~/.ssh/id_ed25519
```
Next, to [add it to GitHub][github], first copy the public key to your
clipboard:
```
$ cat ~/.ssh/id_ed25519.pub
```
Then [add a new SSH key in your GitHub settings][new] by choosing a descriptive
title, pasting the contents of that public key file, and clicking "Add SSH key".
If you're using WSL 2, you'll also want to [make it not repeatedly prompt for
your SSH passphrase][wsl]:
```
$ echo 'eval `keychain --quiet --eval --agents ssh id_rsa`' >> ~/.bashrc
```

[generate]: https://help.github.com/en/github/authenticating-to-github/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent
[github]: https://help.github.com/en/github/authenticating-to-github/adding-a-new-ssh-key-to-your-github-account
[new]: https://github.com/settings/ssh/new
[wsl]: https://stackoverflow.com/a/63803879/5044950
