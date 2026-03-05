# dotfiles

Neovim の設定ファイルを管理するリポジトリ。

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

```bash
git clone https://github.com/aiirononeko/dotfiles.git
cd dotfiles
bash install.sh
```

`install.sh` は `nvim/` ディレクトリを `~/.config/nvim` にシンボリックリンクで配置します。既存の設定がある場合は自動でバックアップされます。
