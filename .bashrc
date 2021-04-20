#!/usr/bin/env bash

# file-level ShellCheck directives
# shellcheck disable=SC1090
# shellcheck disable=SC1091
# shellcheck disable=SC2164

source /etc/skel/.bashrc

eval "$(keychain --quiet --eval --agents ssh id_ed25519)"

if ! __conda_setup="$(~/miniconda3/bin/conda shell.bash hook 2> /dev/null)"; then
    eval "$__conda_setup"
else
    if [ -f "/home/sam/miniconda3/etc/profile.d/conda.sh" ]; then
        . "/home/sam/miniconda3/etc/profile.d/conda.sh"
    else
        export PATH="/home/sam/miniconda3/bin:$PATH"
    fi
fi
unset __conda_setup

source ~/.cargo/env

export NVM_DIR=~/.nvm
[ -s $NVM_DIR/nvm.sh ] && \. $NVM_DIR/nvm.sh # This loads nvm
[ -s $NVM_DIR/bash_completion ] && \. $NVM_DIR/bash_completion # This loads nvm bash_completion

export GEM_HOME=~/gems

source /usr/local/etc/bash_completion.d/deno.bash

export SDKMAN_DIR=~/.sdkman
[[ -s ~/.sdkman/bin/sdkman-init.sh ]] && source ~/.sdkman/bin/sdkman-init.sh

export PATH=~/.local/bin:$PATH
export PATH=~/.yarn/bin:$PATH
export PATH=/usr/local/texlive/2020/bin/x86_64-linux:$PATH
export PATH=~/gems/bin:$PATH

# https://superuser.com/a/1532421
if [ "$PWD" = '/mnt/c/Users/sam' ]
then
  cd
fi
