# ================================
# ENV
# ================================
export EDITOR="nano"
export VISUAL="nano"

# ================================
# PROMPT
# ================================
autoload -Uz colors add-zsh-hook
colors
setopt PROMPT_SUBST

# --- Git branch cache ---
git_info() {
  local branch
  branch=$(git symbolic-ref --short HEAD 2>/dev/null) || return
  print " (%F{cyan}$branch%f)"
}

dir_display() {
  git rev-parse --is-inside-work-tree &>/dev/null
  if [[ $? -eq 0 ]]; then
    # Dentro de repo → só nome da pasta atual
    print "%F{blue}${PWD:t}%f"
  else
    # Fora → caminho normal
    print "%F{blue}%~%f"
  fi
}

PROMPT='%F{green}%n@%m%f:$(dir_display)$(git_info)
$ '

# ================================
# COMPLETION
# ================================
autoload -Uz compinit
compinit -d ~/.zcompdump

zstyle ':completion:*' menu select
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
setopt auto_menu complete_in_word

# ================================
# HISTORY
# ================================
HISTFILE=~/.zsh_history
HISTSIZE=50000
SAVEHIST=50000
setopt HIST_IGNORE_ALL_DUPS HIST_SAVE_NO_DUPS SHARE_HISTORY

# ================================
# QUALITY OF LIFE
# ================================
bindkey -e
setopt auto_cd auto_pushd multios interactivecomments extended_glob

# ================================
# TOOLS
# ================================
export NODE_OPTIONS="--max-old-space-size=4096"

FNM_PATH="$HOME/.local/share/fnm"

if [ -d "$FNM_PATH" ]; then
  export PATH="$FNM_PATH:$PATH"
  eval "$(fnm env --use-on-cd --corepack-enabled --shell zsh)"
fi

eval "$(zoxide init zsh --cmd cd)"

# ================================
# UX
# ================================
source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=245'

source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# fnm
FNM_PATH="/home/heitorrsdev/.local/share/fnm"
if [ -d "$FNM_PATH" ]; then
  export PATH="$FNM_PATH:$PATH"
  eval "$(fnm env --shell zsh)"
fi
