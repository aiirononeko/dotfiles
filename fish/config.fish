if status is-interactive
  # Commands to run in interactive sessions can go here
  eval (/opt/homebrew/bin/brew shellenv)
end

# View
set -g theme_display_date yes
set -g theme_date_format "+%F %H:%M"
set -g theme_display_git_default_branch yes
set -g theme_color_scheme dark

# Path

# Setting
## Peco
set fish_plugins theme peco
function fish_user_key_bindings
  bind \cw peco_select_history
end
set GHQ_SELECTOR peco
set -gx VOLTA_HOME "$HOME/.volta"
set -gx PATH "$VOLTA_HOME/bin" $PATH

# pnpm
set -gx PNPM_HOME "/Users/ryotakatada/Library/pnpm"
if not string match -q -- $PNPM_HOME $PATH
  set -gx PATH "$PNPM_HOME" $PATH
end
# pnpm end

# Alias
## Git
alias g='git'
alias gb='git branch'
alias gc='git commit'
alias gc='git checkout'
alias ga='git add'
alias gp='git push'
alias gl='git log --oneline --graph --decorate --all'

## Lazygit
alias lg='lazygit'

## DockerCompose
alias dc='docker compose'
alias dcu='docker compose up'
alias dce='docker compose exec'

