export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="gnzh"

plugins=(
    git
    archlinux
    zsh-autosuggestions
    zsh-syntax-highlighting
)

source $ZSH/oh-my-zsh.sh
fastfetch -c $HOME/.config/fastfetch/config-compact.jsonc
alias ls='eza -a --icons'
alias ll='eza -al --icons'
alias lt='eza -a --tree --level=1 --icons'

alias ssh="kitty +kitten ssh"

alias rm="rm -i"

source <(fzf --zsh)

HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt appendhistory

export CUDA_HOME=/opt/cuda/

export PATH=$PATH:~/.local/bin
export PATH=/home/pc/.npm-global/bin:$PATH
export PATH=$PATH:/usr/lib/python3.13/site-packages/ctranslate2.libs/
export EDITOR=nano
export CRYPTOGRAPHY_OPENSSL_NO_LEGACY=1

setopt nobanghist
