# Environment

You are in a virtual machine with passwordless `sudo`, a lot of RAM and disk space, and generally free rein to do anything you want, including installing software by whatever mechanism you prefer. The only private or sensitive data in this virtual machine that pose a potential exfiltration risk are credentials for a couple LLM providers; there are no other credentials or private data.

## Links

Anytime you make a claim, think about whether it'd be possible to include a clickable URL that would make it easier for a human to verify that claim. If it is, do so.

## Temporary files

Never put scratch work in a directory like `/tmp` that will get deleted whenever the VM reboots. Instead, do something like this:

```sh
mkdir -p ./scratch && echo '*' > ./scratch/.gitignore
```

## GitHub repositories

The `~/github` directory holds clones of GitHub repositories. Anytime it would be useful to get any information about `github.com/$OWNER/$REPO`, use a clone of that repo in `~/github/$OWNER/$REPO`. Never use any other method to fetch information from GitHub unless the information does not exist in the Git repository itself. If the clone already exists, you may need to `git pull` if the commit you're interested in is more recent. If the clone does not already exist, simply create it and then use that. Since this VM doesn't have GitHub credentials, you need to clone via HTTPS:

```sh
git clone --recursive https://github.com/$OWNER/$REPO ~/github/$OWNER/$REPO
```

Always do a complete clone, with full history and all blobs. Don't try to save time or space with a shallow clone (`--depth`), a partial clone (`--filter=blob:none` or `--filter=tree:0`), or a sparse checkout: information you don't need right now may be useful for some other purpose in the future, and disk space is plentiful.

## Tailscale

There are two other virtual machines on the same tailnet. If you are in one of the Linux VMs, and you need to test something on a different architecture or on macOS, you can SSH into any of the other VMs. (The macOS VM cannot currently do this.) If a VM you want to use is offline, you'd need to ask the human to turn it on before you can use it.

For the `x86_64-linux` VM:

```sh
ssh sandbox-amd64
```

For the `aarch64-linux` VM:

```sh
ssh ubuntu
```

For the `aarch64-darwin` VM:

```sh
ssh tahoe-vanilla
```
