#!/bin/bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
NVIM_CONFIG_DIR="${HOME}/.config/nvim"
ZSHRC_SRC="${DOTFILES_DIR}/.zshrc"
ZSHRC_DST="${HOME}/.zshrc"
BIN_DIR="${HOME}/.local/bin"

echo "=== dotfiles installer ==="

# ~/.config が無ければ作成
mkdir -p "${HOME}/.config"

# --- Helper: シンボリックリンク作成 ---
link_file() {
  local src="$1"
  local dst="$2"
  local name="$3"

  # 既存のファイル（シンボリックリンクではない）をバックアップ
  if [ -e "$dst" ] && [ ! -L "$dst" ]; then
    local backup="${dst}.bak.$(date +%Y%m%d%H%M%S)"
    echo "Backing up existing ${name} config to ${backup}"
    mv "$dst" "$backup"
  fi

  # シンボリックリンクが既に正しければスキップ
  if [ -L "$dst" ] && [ "$(readlink "$dst")" = "$src" ]; then
    echo "${name} symlink already exists and is correct."
  else
    # 既存のシンボリックリンクがあれば削除
    [ -L "$dst" ] && rm "$dst"
    ln -s "$src" "$dst"
    echo "Created symlink: ${dst} -> ${src}"
  fi
}

# --- nvim ---
link_file "${DOTFILES_DIR}/nvim" "$NVIM_CONFIG_DIR" "nvim"

# --- zsh ---
link_file "$ZSHRC_SRC" "$ZSHRC_DST" "zshrc"

# --- IME tools (Neovim normal-mode force English) ---
install_macos_ime_tool() {
  if command -v im-select >/dev/null 2>&1; then
    echo "im-select is already installed."
    return
  fi

  if ! command -v brew >/dev/null 2>&1; then
    echo "Skipping im-select install: Homebrew is not available."
    return
  fi

  echo "Installing im-select (macOS)..."
  brew tap daipeihust/tap
  brew install im-select
}

install_wsl_ime_tool() {
  mkdir -p "$BIN_DIR"

  if command -v zenhan.exe >/dev/null 2>&1 || [ -x "${BIN_DIR}/zenhan.exe" ]; then
    echo "zenhan.exe is already installed."
    return
  fi

  local zenhan_url="https://github.com/iuchim/zenhan/releases/download/v0.0.1/zenhan.zip"
  local zenhan_zip="/tmp/zenhan.zip"
  local zenhan_dst="${BIN_DIR}/zenhan.exe"

  echo "Installing zenhan.exe (WSL2)..."
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$zenhan_url" -o "$zenhan_zip"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$zenhan_zip" "$zenhan_url"
  else
    echo "Skipping zenhan.exe install: curl or wget is required."
    return
  fi

  unzip -o "$zenhan_zip" zenhan.exe -d "$BIN_DIR"
  rm -f "$zenhan_zip"
  chmod +x "$zenhan_dst"
}

OS="$(uname -s)"
if [ "$OS" = "Darwin" ]; then
  install_macos_ime_tool
elif grep -qi microsoft /proc/version 2>/dev/null; then
  install_wsl_ime_tool
fi

echo "Done!"
