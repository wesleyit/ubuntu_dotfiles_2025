# Set up the prompt

setopt histignorealldups sharehistory

# Use emacs keybindings even if our EDITOR is set to vi
bindkey -e

HISTSIZE=1000
SAVEHIST=1000
HISTFILE=~/.zsh_history

source "$HOME/.asdf/asdf.sh"
fpath=(${ASDF_DIR}/completions $fpath)
autoload -Uz compinit && compinit

# Autosuggestions
source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh

# Path
export PATH=~/.local/bin:$PATH

# Starfish Prompt
eval "$(starship init zsh)"

# Reload
alias reload="source ~/.zshrc"
alias editzshrc="vim ~/.zshrc"
alias ls="exa --icons"
alias vim="lvim"

# Este deve ir no fim
source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
