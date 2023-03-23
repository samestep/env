### macOS

## softwares (alphabetical)

# Cargo
source ~/.cargo/env

# Emscripten
if [ -f ~/github/emscripten-core/emsdk/emsdk_env.sh ]; then
    export EMSDK_QUIET=1
    source ~/github/emscripten-core/emsdk/emsdk_env.sh
fi

# nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# opam
[[ ! -r ~/.opam/opam-init/init.zsh ]] || source ~/.opam/opam-init/init.zsh  > /dev/null 2> /dev/null

# Starship
eval "$(starship init zsh)"

# XCode
export SDKROOT=$(xcrun --show-sdk-path)

## PATH (alphabetical)
export PATH=~/.config/yarn/global/node_modules/.bin:$PATH
export PATH=~/.deno/bin:$PATH
export PATH=~/.gem/ruby/X.X.0/bin:$PATH
export PATH=~/.local/bin:$PATH
export PATH=~/.yarn/bin:$PATH
export PATH=~/bin:$PATH
export PATH=~/Library/Python/3.9/bin:$PATH

## tab completion

fpath+=~/.zfunc
autoload -Uz compinit && compinit

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
