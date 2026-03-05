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

1. `core/options.lua` — Vim オプション
2. `core/keymaps.lua` — キーマッピング + which-key 説明の日英切替
3. `core/lazy.lua` — lazy.nvim ブートストラップ + `plugins/` ディレクトリの自動読み込み
4. `core/autocmds.lua` — 起動時に Neo-tree を自動で開く
5. `core/ime.lua` — IME 自動切替（ノーマルモード復帰時に英語入力へ強制切替）
6. `ui/cheatbar.lua` — Vim チートシートのフロート表示
7. `ui/claude_float.lua` — Claude Code フローティングターミナル

## プラグイン管理

lazy.nvim を使用。プラグイン定義は `nvim/lua/plugins/` ディレクトリに個別ファイルとして配置（import パターン）。`nvim/lazy-lock.json` でバージョンをロック。

主要プラグイン: tokyonight (カラースキーム), which-key, neo-tree, telescope, gitsigns, diffview, lazygit

## 編集時の注意

- Leader キーは `<Space>`
- キーマッピングの説明は日本語/英語の両方を `descriptions` テーブルで管理している (`keymaps.lua`)。キーを追加する場合は両言語の説明を追加すること
- `ui/cheatbar.lua` 内の `cheatsheet` テーブルにVimチップスが定義されている。ステータスライン上のフロートバーに30秒ごとにランダム表示される
- プラグインを追加する場合は `nvim/lua/plugins/` に新しいファイルを作成し、プラグインspecテーブルを `return` する
- `.zshrc` は macOS / Linux 両対応。OS 判定で分岐している箇所がある
