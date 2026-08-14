# gitwalk.nvim

Navigate `git diff` as a tree of **hunks**, not files — review moves
change-by-change, with a live preview and jump-to-exact-line.

```
▼ lib
  ▼ auth
    ▼ login.dart [+17 -4] [3]
      ├─ ① loading state       L18
      ├─ ② authentication      L47
      └─ ③ error handling      L103
```

`j`/`k` moves node-to-node (hunks once a file is expanded); the floating
preview shows just that hunk's diff, not the whole file. `<CR>` drops your
cursor on the exact changed line in a real window.

## Status

MVP implemented: async git diff parsing, hunk tree, floating chunk-only
preview (delta-rendered when available), jump, hunk/file staging,
`:checkhealth`. See [`PLAN.md`](./PLAN.md) for the full architecture and
roadmap.

## Requirements

- Neovim ≥ 0.10
- `git` on `$PATH`
- [delta](https://github.com/dandavison/delta) (optional) — syntax-highlighted,
  colorized preview; without it the preview falls back to plain
  `filetype=diff` highlighting
- [nvim-web-devicons](https://github.com/nvim-tree/nvim-web-devicons) (optional)

## Install (lazy.nvim)

```lua
{
  "olamilekan-adeleke/gitwalk.nvim",
  cmd = { "Gitwalk", "GitwalkToggle", "GitwalkRefresh" },
  opts = {},
}
```

## Usage

```vim
:Gitwalk         " open the hunk-tree panel
:GitwalkToggle   " toggle it
:GitwalkRefresh  " re-run git diff, keep expand state
```

| Key | Action |
|---|---|
| `j` / `k` | move to next/prev node, updates preview |
| `<CR>` | jump: move editing focus to the hunk's changed line |
| `l` / `h` | expand / collapse |
| `<Tab>` | toggle expand/collapse |
| `r` | refresh |
| `s` / `S` | stage hunk / stage file |
| `q` | close |

All keymaps are configurable via `setup()` — see `:help gitwalk-config`.

## Configuration

```lua
require("gitwalk").setup({
  width = 40,
  position = "left", -- "left" | "right"
  icons = true,
  sign_column = true,
  diff_context = 0,
  keymaps = { --[[ see :help gitwalk-config ]] },
})
```

## Testing

```bash
git clone --depth 1 https://github.com/nvim-lua/plenary.nvim /tmp/plenary.nvim
PLENARY_DIR=/tmp/plenary.nvim nvim --headless -u tests/minimal_init.lua \
  -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"
```

## License

MIT — see [`LICENSE`](./LICENSE).
