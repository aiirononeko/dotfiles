# dotfiles

Neovim + シェル の設定ファイルを管理するリポジトリ。macOS / Linux (WSL2) / Windows に対応。

## 構成

```
nvim/
├── init.lua              # エントリポイント
├── lazy-lock.json        # プラグインのバージョンロック
└── lua/core/
    ├── options.lua        # Vim オプション設定
    ├── keymaps.lua        # キーマッピング定義
    └── lazy.lua           # プラグイン管理 (lazy.nvim)
```

## プラグイン

| プラグイン | 用途 |
|---|---|
| [folke/tokyonight.nvim](https://github.com/folke/tokyonight.nvim) | カラースキーム (storm / transparent) |
| [folke/which-key.nvim](https://github.com/folke/which-key.nvim) | キーバインドのツールチップ表示 |
| [nvim-neo-tree/neo-tree.nvim](https://github.com/nvim-neo-tree/neo-tree.nvim) | ファイラー |
| [echasnovski/mini.pick](https://github.com/echasnovski/mini.pick) | ファジーファインダー |

## キーマッピング

Leader キーは `<Space>`。

| キー | 動作 |
|---|---|
| `jj` (insert) | ノーマルモードに戻る |
| `<C-h/j/k/l>` | ウィンドウ間移動 |
| `<leader>f` | ファイル検索 |
| `<leader>g` | テキスト検索 (grep) |
| `<leader>b` | バッファ一覧 |
| `<leader>e` | ファイルツリー切替 |
| `<leader>h` | 検索ハイライト消去 |
| `<leader>w` | 保存 |
| `<leader>qq` | 閉じる |
| `<leader>x` | 保存して閉じる |
| `<leader>?` | 説明の日本語/英語切替 |

## セットアップ

### macOS / Linux (WSL2)

```bash
git clone https://github.com/aiirononeko/dotfiles.git
cd dotfiles
bash install.sh
```

`install.sh` は以下をシンボリックリンクで配置します:
- `nvim/` → `~/.config/nvim`
- `.zshrc` → `~/.zshrc`

### Windows

```powershell
git clone https://github.com/aiirononeko/dotfiles.git
cd dotfiles
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

`install.ps1` は以下をシンボリックリンクで配置します:
- `nvim/` → `%LOCALAPPDATA%\nvim`
- `.ps_profile.ps1` → PowerShell プロファイル (`$PROFILE`)
- `im-select.exe` のインストール（winget 優先、GitHub Releases フォールバック）

> **Note:** シンボリックリンクの作成には「開発者モード」の有効化、または管理者権限での実行が必要です。無効な場合はコピーにフォールバックします。

既存の設定がある場合は自動でバックアップされます。
