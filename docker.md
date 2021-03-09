# Docker

Follow the [official installation instructions][install]. First update APT:
```
$ sudo apt update
```
Then install some prerequisites:
```
$ sudo apt install apt-transport-https ca-certificates curl gnupg-agent software-properties-common
```
And add the Docker GPG key:
```
$ curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
```
Check that it worked:
```
$ sudo apt-key fingerprint 0EBFCD88
```
Now add the stable repository:
```
$ sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
```
Update APT again:
```
$ sudo apt update
```
And install Docker:
```
$ sudo apt install docker-ce docker-ce-cli containerd.io
```
Next follow the [official post-installation instructions][post] to make it work
without `sudo`:
```
$ sudo usermod -aG docker $USER
```
Reboot:
```
$ reboot
```
If you're using WSL, you'll also need to [install Docker on the Windows
side][wsl]. Finally, verify that it worked:
```
$ docker run hello-world
```

[install]: https://docs.docker.com/engine/install/ubuntu/#install-using-the-repository
[post]: https://docs.docker.com/engine/install/linux-postinstall/#manage-docker-as-a-non-root-user
[wsl]: https://docs.docker.com/docker-for-windows/wsl/
