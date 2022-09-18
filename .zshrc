### macOS

## softwares (alphabetical)

# Cargo
source ~/.cargo/env

# conda
__conda_setup="$(~/anaconda3/bin/conda 'shell.zsh' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "$HOME/anaconda3/etc/profile.d/conda.sh" ]; then
        . "$HOME/anaconda3/etc/profile.d/conda.sh"
    else
        export PATH="$HOME/anaconda3/bin:$PATH"
    fi
fi
unset __conda_setup

# nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# opam
[[ ! -r ~/.opam/opam-init/init.zsh ]] || source ~/.opam/opam-init/init.zsh  > /dev/null 2> /dev/null

# pyenv
eval "$(pyenv init -)"

# Starship
eval "$(starship init zsh)"

# XCode
export SDKROOT=$(xcrun --show-sdk-path)

## PATH (alphabetical)
export PATH=~/.config/yarn/global/node_modules/.bin:$PATH
export PATH=~/.gem/ruby/X.X.0/bin:$PATH
export PATH=~/.local/bin:$PATH
export PATH=~/.yarn/bin:$PATH
export PATH=~/bin:$PATH

## aliases

alias ls=exa

## functions

function ghcode() {
    local repo=${1#https://github.com/}
    local folder=~/github/$repo
    if [ ! -d "$folder" ]; then
        rm -f "$folder"
        gh repo clone "$repo" "$folder"
    fi
    code "$folder"
}
