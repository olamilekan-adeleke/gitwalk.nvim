# gitwalk.nvim

A fuzzy-finder-style picker over `git diff`, where the results are **hunks**,
not files — browse change-by-change, filter to find one fast, `<CR>` jumps
straight to it.

```
╭─ gitwalk ──────────╮╭─ preview ──────────────────────────╮
│ > auth              ││ lib/auth/login.dart                │
├──────────────────────┤├──────────────────────────────────┤
│ ▼ lib                ││ 16: class Login {                 │
│   ▼ auth              ││   bool loading = false;           │
│     ▼ login.dart [3]  ││                                    │
│       ① loading  L18  ││   Future<void> login() async {    │
│       ② auth     L47  ││   }                                │
│       ③ error    L103 ││                                    │
╰──────────────────────╯╰──────────────────────────────────╯
```

Leave the filter empty to browse the collapsible dir/file/hunk tree; start
typing to fuzzy-filter straight to a file or hunk across the whole diff, like
a fuzzy finder. The preview shows only the selected hunk's diff (not the
whole file), rendered through `delta` when it's installed.

## Status

MVP implemented: async git diff parsing, hunk tree, fuzzy-filterable modal
picker, delta-rendered chunk-only preview, jump, hunk/file staging,
`:checkhealth`. See [`PLAN.md`](./PLAN.md) for the full architecture and
roadmap.

## Requirements

- Neovim ≥ 0.10
- `git` on `$PATH`
- [delta](https://github.com/dandavison/delta) (optional) — syntax-highlighted,
  colorized preview; without it the preview falls back to plain
  `filetype=diff` highlighting

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
:Gitwalk         " open the picker
:GitwalkToggle   " toggle it
:GitwalkRefresh  " re-run git diff without closing the picker
```

You start in insert mode in the filter prompt — just type to fuzzy-filter.

| Key | Action |
|---|---|
| *(type)* | fuzzy-filter files/hunks across the whole diff |
| `<C-n>` / `<C-p>` | next / previous item |
| `<CR>` | jump: close the picker and move editing focus to the hunk's line |
| `<Tab>` | expand/collapse the node under the selection (empty filter only) |
| `<C-r>` | refresh (re-run git diff) |
| `<C-s>` / `<C-x>` | stage hunk / stage file under the selection |
| `<Esc>` | close |

All keymaps are configurable via `setup()` — see `:help gitwalk-config`.

## Configuration

```lua
require("gitwalk").setup({
  width = 0.9,       -- fraction of columns for the whole modal
  height = 0.85,      -- fraction of lines for the whole modal
  list_ratio = 0.4,   -- fraction of modal width given to the list pane
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
