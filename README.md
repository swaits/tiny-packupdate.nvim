# tiny-packupdate.nvim

A tiny, opinionated plugin updater for Neovim 0.12+'s native `vim.pack`.

Smooth animated progress bar. Commit-level changelogs.
[snacks.nvim](https://github.com/folke/snacks.nvim) picker integration with
floating markdown fallback. ~250 lines of Lua.

https://github.com/user-attachments/assets/TODO-SCREENCAST

## Features

- Centered floating progress bar with smooth 60fps animation
- Post-update results showing only plugins that changed
- Commit log preview per plugin (with rollback detection)
- [snacks.nvim](https://github.com/folke/snacks.nvim) picker with git-highlighted preview pane
- Floating markdown window fallback when snacks is unavailable
- Auto-update cadence: `manual`, `daily`, `weekly`, or `monthly`
- Single command, single file, zero dependencies

## Requirements

- Neovim >= 0.12 (for `vim.pack` API)
- Optional: [snacks.nvim](https://github.com/folke/snacks.nvim) for picker UI

## Installation

Add to your `vim.pack.add()` call:

```lua
"https://github.com/swaits/tiny-packupdate.nvim",
```

Then in your config:

```lua
require("tiny-packupdate").setup()
```

## Configuration

All options shown with defaults:

```lua
require("tiny-packupdate").setup({
  command = "PackUpdate", -- user command name
  auto = "manual",        -- "manual" | "daily" | "weekly" | "monthly"
  picker = true,          -- use snacks.picker when available (false = always use fallback)
})
```

## Usage

```vim
:PackUpdate
```

The progress bar appears while `vim.pack.update()` runs. When complete:

- **With snacks.nvim**: an ivy-layout picker opens. Plugin names on the left,
  commit log on the right. Fuzzy-searchable.
- **Without snacks.nvim**: a floating markdown window shows all changes.
  Press `q` or `<Esc>` to close.
- **No changes**: a simple notification — "All plugins up to date".

### Auto-update

Set `auto` to `"daily"`, `"weekly"`, or `"monthly"` and updates run
automatically on startup when the interval has elapsed. The last update
timestamp is stored at `vim.fn.stdpath("data") .. "/tiny-packupdate-last"`.

## Highlights

| Group | Default | Description |
|---|---|---|
| `TinyPackProgress` | links to `DiagnosticOk` | Filled portion of the progress bar |

Override in your colorscheme or after setup:

```lua
vim.api.nvim_set_hl(0, "TinyPackProgress", { fg = "#a6e3a1" })
```

## How it works

1. Snapshots all active plugin revisions via `vim.pack.get()`
2. Calls `vim.pack.update()` with `force = true`
3. Listens for `PackChanged` autocmd events to count updates
4. Uses a 2-second debounce timer to detect completion
5. Compares post-update revisions against the snapshot
6. Runs async `git log` for each changed plugin
7. Displays results in your preferred UI

### Rollback detection

When a plugin moves backward in history (e.g. downgrading a pinned version),
the commit log is labeled `(rolled back past)` and shows the commits that were
reverted.

## Caveats

- Only updates plugins already loaded via `vim.pack.add()`. If you just added a
  new plugin to your config but haven't restarted, it won't be included.
- The progress bar is time-based (smooth asymptotic fill). Neovim's `vim.pack`
  API fires `PackChanged` events only for plugins that actually change, so a
  traditional done/total bar isn't possible.
- The debounce timeout (2 seconds) means there's a brief pause after the last
  plugin updates before results appear.

## License

[MIT](LICENSE)
