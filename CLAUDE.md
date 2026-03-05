# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Neovim + zsh の設定ファイル(dotfiles)を管理するリポジトリ。macOS / Linux (WSL2) の両環境に対応。

## セットアップ

```bash
bash install.sh
```

`install.sh` は以下をシンボリックリンクで配置する:
- `nvim/` → `~/.config/nvim`
- `.zshrc` → `~/.zshrc`

既存ファイルがある場合は `.bak.{timestamp}` でバックアップされる。

## Neovim 設定の構成

エントリポイントは `nvim/init.lua`。以下の順で読み込まれる:

1. `core/options.lua` — Vim オプション + Vim チートシートのフロート表示
2. `core/keymaps.lua` — キーマッピング + Claude Code フローティングターミナル + which-key 説明の日英切替
3. `core/lazy.lua` — lazy.nvim によるプラグイン管理
4. `core/autocmds.lua` — 起動時に Neo-tree を自動で開く + IME 自動切替（ノーマルモード復帰時に英語入力へ強制切替）

## プラグイン管理

lazy.nvim を使用。プラグイン定義は `nvim/lua/core/lazy.lua` に集約。`nvim/lazy-lock.json` でバージョンをロック。

主要プラグイン: tokyonight (カラースキーム), which-key, neo-tree, telescope, gitsigns, diffview, lazygit

## 編集時の注意

- Leader キーは `<Space>`
- キーマッピングの説明は日本語/英語の両方を `descriptions` テーブルで管理している (`keymaps.lua`)。キーを追加する場合は両言語の説明を追加すること
- `options.lua` 内の `cheatsheet` テーブルにVimチップスが定義されている。ステータスライン上のフロートバーに30秒ごとにランダム表示される
- `.zshrc` は macOS / Linux 両対応。OS 判定で分岐している箇所がある
