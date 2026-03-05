# --- OS detection ---
case "$(uname -s)" in
  Linux*)  export IS_LINUX=true; export IS_MAC=false ;;
  Darwin*) export IS_MAC=true; export IS_LINUX=false ;;
esac

# --- Homebrew ---
if [[ "$IS_MAC" == "true" ]]; then
  # Apple Silicon
  if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  # Intel Mac
  elif [[ -f /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
elif [[ "$IS_LINUX" == "true" ]]; then
  if [[ -f /home/linuxbrew/.linuxbrew/bin/brew ]]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
  fi
fi

# --- PATH ---
export PATH="$HOME/.local/bin:$PATH"

# --- Editor ---
export EDITOR='nvim'

# --- mise (runtime version manager) ---
if command -v mise &>/dev/null; then
  eval "$(mise activate zsh)"
fi

# --- direnv ---
if command -v direnv &>/dev/null; then
  eval "$(direnv hook zsh)"
fi

# --- bun ---
if [[ -d "$HOME/.bun" ]]; then
  export BUN_INSTALL="$HOME/.bun"
  export PATH="$BUN_INSTALL/bin:$PATH"
  [[ -s "$BUN_INSTALL/_bun" ]] && source "$BUN_INSTALL/_bun"
fi

# --- fzf + ghq ---
function _fzf_cd_ghq() {
    FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS} --reverse --height=50%"
    local root="$(ghq root)"
    local repo="$(ghq list | fzf --preview="ls -AF --color=always ${root}/{1}")"
    local dir="${root}/${repo}"
    [ -n "${repo}" ] && cd "${dir}"
    zle accept-line
    zle reset-prompt
}
zle -N _fzf_cd_ghq
bindkey "^g" _fzf_cd_ghq

# --- Aliases ---
alias cc='claude --dangerously-skip-permissions'
alias vim='nvim'

# --- Claude Code ---
export CLAUDE_CODE_GIT_BASH_PATH=/usr/bin/git

# --- OS-specific settings ---
if [[ "$IS_LINUX" == "true" ]]; then
  # WSL-specific settings
  export PICO_SDK_PATH=~/pico/pico-sdk
fi

