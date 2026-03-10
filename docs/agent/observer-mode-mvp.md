# Observer Mode MVP

## Intent

This repository now includes a dedicated Neovim observer view for Claude/AI-agent operations.

The panel is intentionally read-only:
- it shows harness health first,
- keeps session summary secondary,
- launches Claude Code for remediation,
- does not turn Neovim into a chat surface or code editor.

## Current Entry Point

- Toggle the observer view with `<leader>co`
- The panel lives in `nvim/lua/ui/claude_observer.lua`
- The observer model lives in `nvim/lua/claude/observer_state.lua`

## MVP Notes

- Source of truth is structured Claude session data under `~/.claude/history.jsonl` and `~/.claude/projects/.../*.jsonl`
- Harness coverage is intentionally coarse: `ok`, `weak`, `missing`
- Claude remediation actions are prompt launchers only; edits still happen in Claude Code

## Verification

Minimal smoke check used during implementation:

```bash
XDG_CACHE_HOME=/tmp/codex-nvim-cache \
XDG_STATE_HOME=/tmp/codex-nvim-state \
XDG_DATA_HOME=/tmp/codex-nvim-data \
NVIM_APPNAME=codex-observer-test \
nvim --headless \
  "+lua package.path = vim.fn.getcwd() .. '/nvim/lua/?.lua;' .. vim.fn.getcwd() .. '/nvim/lua/?/init.lua;' .. package.path" \
  "+lua require('ui.claude_observer').open(); require('ui.claude_observer').close()" \
  +qa
```

## Planned Scope Reconciliation

- Done: structured session health model
- Done: dedicated right-side observer panel
- Done: grounded action launcher prompts into Claude Code
- Done: compact session inspection and session switching
- Out of scope: in-panel editing
- Out of scope: full chat UI
- Out of scope: scoring/benchmark framework
