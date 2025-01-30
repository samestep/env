### macOS

## softwares (alphabetical)

# Bun
export BUN_INSTALL=~/.bun
[ -s "$BUN_INSTALL/_bun" ] && source "$BUN_INSTALL/_bun"

# Cargo
source ~/.cargo/env

# chruby
source $HOMEBREW_PREFIX/opt/chruby/share/chruby/chruby.sh
source $HOMEBREW_PREFIX/opt/chruby/share/chruby/auto.sh

# Emscripten
if [ -f ~/github/emscripten-core/emsdk/emsdk_env.sh ]; then
    export EMSDK_QUIET=1
    source ~/github/emscripten-core/emsdk/emsdk_env.sh
fi

# Homebrew
eval "$(/opt/homebrew/bin/brew shellenv)"

# nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# opam
[[ ! -r ~/.opam/opam-init/init.zsh ]] || source ~/.opam/opam-init/init.zsh  > /dev/null 2> /dev/null

# Starship
eval "$(starship init zsh)"

# Wasmtime
export WASMTIME_HOME="$HOME/.wasmtime"

# XCode
export SDKROOT=$(xcrun --show-sdk-path)

## PATH (alphabetical)
export PATH=/opt/homebrew/opt/llvm@16/bin:$PATH
export PATH=~/.bun/bin:$PATH
export PATH=~/.config/yarn/global/node_modules/.bin:$PATH
export PATH=~/.deno/bin:$PATH
export PATH=~/.elan/bin:$PATH
export PATH=~/.juliaup/bin:$PATH
export PATH=~/.local/bin:$PATH
export PATH=~/.wasmtime/bin:$PATH
export PATH=~/.yarn/bin:$PATH
export PATH=~/bin:$PATH
export PATH=~/go/bin:$PATH

## tab completion

fpath+=~/.zfunc
autoload -Uz compinit && compinit

## aliases

alias ls=eza
alias sed=gsed

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

# bun completions
[ -s "/Users/samueles/.bun/_bun" ] && source "/Users/samueles/.bun/_bun"
