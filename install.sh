#!/bin/bash
set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"
NVIM_CONFIG_DIR="${HOME}/.config/nvim"

echo "=== dotfiles installer ==="

# ~/.config が無ければ作成
mkdir -p "${HOME}/.config"

# 既存の nvim 設定をバックアップ
if [ -e "$NVIM_CONFIG_DIR" ] && [ ! -L "$NVIM_CONFIG_DIR" ]; then
  BACKUP="${NVIM_CONFIG_DIR}.bak.$(date +%Y%m%d%H%M%S)"
  echo "Backing up existing nvim config to ${BACKUP}"
  mv "$NVIM_CONFIG_DIR" "$BACKUP"
fi

# シンボリックリンクが既に正しければスキップ
if [ -L "$NVIM_CONFIG_DIR" ] && [ "$(readlink "$NVIM_CONFIG_DIR")" = "${DOTFILES_DIR}/nvim" ]; then
  echo "nvim symlink already exists and is correct."
else
  # 既存のシンボリックリンクがあれば削除
  [ -L "$NVIM_CONFIG_DIR" ] && rm "$NVIM_CONFIG_DIR"
  ln -s "${DOTFILES_DIR}/nvim" "$NVIM_CONFIG_DIR"
  echo "Created symlink: ${NVIM_CONFIG_DIR} -> ${DOTFILES_DIR}/nvim"
fi

echo "Done!"
