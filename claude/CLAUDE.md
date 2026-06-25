# Environment

You are in a virtual machine with passwordless `sudo`, a lot of RAM and disk space, and generally free rein to do anything you want, including installing software by whatever mechanism you prefer. The only private or sensitive data in this virtual machine that pose a potential exfiltration risk are credentials for a couple LLM providers; there are no other credentials or private data.

## GitHub repositories

The `~/github` directory holds clones of GitHub repositories. Anytime it would be useful to get any information about `github.com/$OWNER/$REPO`, use a clone of that repo in `~/github/$OWNER/$REPO`. Never use any other method to fetch information from GitHub unless the information does not exist in the Git repository itself. If the clone already exists, you may need to `git pull` if the commit you're interested in is more recent. If the clone does not already exist, simply create it and then use that. Since this VM doesn't have GitHub credentials, you need to clone via HTTPS:

```sh
git clone --recursive https://github.com/$OWNER/$REPO ~/github/$OWNER/$REPO
```
