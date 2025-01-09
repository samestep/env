#!/usr/bin/env bash

### Ubuntu

## file-level ShellCheck directives
# shellcheck disable=SC1090
# shellcheck disable=SC1091
# shellcheck disable=SC2164

## Ubuntu default .bashrc
source /etc/skel/.bashrc

## softwares (alphabetical)

# Cargo
if [ -f ~/.cargo/env ]; then
    source ~/.cargo/env
fi

# conda
if ! __conda_setup="$(~/miniconda3/bin/conda shell.bash hook 2> /dev/null)"; then
    eval "$__conda_setup"
else
    if [ -f "$HOME/miniconda3/etc/profile.d/conda.sh" ]; then
        . "$HOME/miniconda3/etc/profile.d/conda.sh"
    else
        export PATH="$HOME/miniconda3/bin:$PATH"
    fi
fi
unset __conda_setup

# Deno
if [ -f /usr/local/etc/bash_completion.d/deno.bash ]; then
    source /usr/local/etc/bash_completion.d/deno.bash
fi

# keychain
if which keychain > /dev/null; then
    eval "$(keychain --quiet --eval --agents ssh id_ed25519)"
fi

# nvm
export NVM_DIR=~/.nvm
[ -s $NVM_DIR/nvm.sh ] && \. $NVM_DIR/nvm.sh # This loads nvm
[ -s $NVM_DIR/bash_completion ] && \. $NVM_DIR/bash_completion # This loads nvm bash_completion

# Ruby
export GEM_HOME=~/gems

# SDKMAN!
export SDKMAN_DIR=~/.sdkman
[[ -s ~/.sdkman/bin/sdkman-init.sh ]] && source ~/.sdkman/bin/sdkman-init.sh

if [ -f /home/linuxbrew/.linuxbrew/bin/brew ]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
fi

# Starship
if which starship > /dev/null; then
  eval "$(starship init bash)"
fi

## PATH (alphabetical)
export PATH=/usr/local/texlive/2020/bin/x86_64-linux:$PATH
export PATH=~/.deno/bin:$PATH
export PATH=~/.elan/bin:$PATH
export PATH=~/.local/bin:$PATH
export PATH=~/.yarn/bin:$PATH
export PATH=~/bin:$PATH
export PATH=~/gems/bin:$PATH
export PATH=~/github/phacility/arcanist/bin:$PATH

## functions

function ghcode() {
    local repo=${1#https://github.com/}
    local folder=~/github/$repo
    if [ ! -d "$folder" ]; then
        rm -f "$folder"
        gh repo clone "$repo" "$folder" -- --recurse-submodules
    fi
    if [ -d "$folder" ]; then
        code "$folder"
    else
        false
    fi
}

## use home directory as WSL default directory
# https://superuser.com/a/1532421
if [ "$PWD" = "/mnt/c/Users/$USER" ]; then
  cd
fi
