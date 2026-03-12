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
function repo() {
  local root="$(ghq root)"
  local repo="$(ghq list | fzf --reverse --height=50% --preview="ls -AF --color=always ${root}/{1}")"
  [ -n "${repo}" ] && cd "${root}/${repo}"
}

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

# --- Oh My Posh (prompt theme) ---
if command -v oh-my-posh &>/dev/null; then
  eval "$(oh-my-posh init zsh --config ~/.config/ohmyposh/takuya.omp.json)"
fi

# --- Aliases ---
alias cc='claude --dangerously-skip-permissions'
alias vim='nvim'
if command -v eza &>/dev/null; then
  alias ls='eza --icons'
  alias ll='eza -l -g --icons'
  alias la='eza -la -g --icons'
fi

# --- Claude Code ---
export CLAUDE_CODE_GIT_BASH_PATH=/usr/bin/git

# --- OS-specific settings ---
if [[ "$IS_LINUX" == "true" ]]; then
  # WSL-specific settings
  export PICO_SDK_PATH=~/pico/pico-sdk
fi

