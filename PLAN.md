# gitwalk.nvim — Build Plan

A Neovim plugin that turns `git diff` into a navigable tree of **hunks**, not files —
so review/navigation moves change-by-change instead of file-by-file, with a live
preview and jump-to-exact-line on `<CR>`.

## 1. Core concept

Two layers of hierarchy, only one of which is really "selectable":

```
lib/auth/login.dart [+17 -4] [3]
  ① loading state      L18
  ② authentication     L47
  ③ error handling     L103
```

- **Structural nodes** (dirs, files) — collapsible, mostly navigational.
- **Hunk nodes** — the real unit of interest. `j`/`k` moves hunk-to-hunk within
  an expanded file; `<CR>` jumps the real buffer cursor to that hunk's first
  changed line.

## 2. Data model

```lua
---@class Hunk
---@field index integer         -- 1-based within file
---@field old_start integer
---@field old_count integer
---@field new_start integer
---@field new_count integer
---@field context string?       -- text after the second @@, e.g. "Future<void> login()"
---@field additions integer
---@field deletions integer
---@field lines string[]        -- raw diff lines for this hunk (for preview)

---@class FileChange
---@field path string           -- repo-relative
---@field status "M"|"A"|"D"|"R"|"?"
---@field additions integer
---@field deletions integer
---@field hunks Hunk[]

---@class TreeNode
---@field type "dir"|"file"|"hunk"
---@field name string
---@field children TreeNode[]?
---@field file FileChange?
---@field hunk Hunk?
---@field expanded boolean
---@field depth integer
```

`FileChange[]` is the source of truth; the directory tree is a derived,
purely-presentational grouping built by splitting each path on `/` and
merging shared prefixes (same algorithm as nvim-tree/oil.nvim use).

## 3. Git integration

- Enumerate changed files: `git diff --name-status` (unstaged) and
  `git diff --cached --name-status` (staged) — support a mode toggle.
- Per-file hunks: `git diff --unified=0 -- <path>` parsed for `@@ -a,b +c,d @@ context`
  headers. `--unified=0` gives exact changed-line ranges without needing to
  walk context lines.
- Full hunk body (with surrounding context, for the preview pane) fetched
  separately with `git diff --unified=3 -- <path>` or by reading the live
  buffer around `new_start`.
- Untracked files: `git ls-files --others --exclude-standard`, treated as a
  single synthetic "whole file" hunk.
- All git calls via `vim.system()` (async, Neovim ≥0.10), never blocking the UI.
  Debounce/re-run on `FocusGained`, `BufWritePost`, and a manual refresh keymap.
- Hunk "context" string: use the text git already appends after the second
  `@@` (it's usually the enclosing function/class signature via git's builtin
  heuristic per filetype). Fallback to `"Changes around line N"` if empty.
  Treesitter-based smarter naming (walk up to nearest function/class node at
  `new_start`) is a **post-MVP** enhancement, not a dependency for v1.

## 4. UI

- Left pane: tree view in a fixed-width vertical split or floating window
  (reuse the split/float choice `neo-tree`/`nvim-tree` make — a real split is
  friendlier for a "stay open while you work" panel).
- Right pane (or bottom, on narrow screens): preview window showing the
  target file's buffer, synced via `nvim_win_set_cursor` + `zz`, with the
  hunk's changed lines highlighted (extmarks, sign column `+`/`-` like gitsigns).
- Render tree as plain lines in a scratch buffer (`buftype=nofile`), one
  line per node, indentation by depth, icons via `nvim-web-devicons` if
  present (optional dependency, degrade gracefully without it).
- Syntax/highlight groups: `GitwalkDir`, `GitwalkFile`, `GitwalkHunkAdd`,
  `GitwalkHunkDel`, `GitwalkStat` — all linked to sane defaults, overridable.

## 5. Keymaps (buffer-local, in the tree buffer)

| Key | Action |
|---|---|
| `j` / `k` | next/prev **selectable** node (hunk if file expanded, else file/dir) |
| `<CR>` | jump: open file in previous window, cursor to hunk's first changed line |
| `o` / `l` | expand node |
| `h` | collapse node / go to parent |
| `<Tab>` | expand/collapse toggle without leaving tree |
| `r` | refresh (re-run git diff) |
| `s` | stage hunk (`git apply --cached` on a synthesized single-hunk patch) |
| `S` | stage file |
| `q` | close |

## 6. Module layout

Superseded by the actual implementation (evolved from the original
sidebar+split-preview design in this plan to a Telescope-style modal
picker):

```
gitwalk.nvim/
├── lua/gitwalk/
│   ├── init.lua          -- setup(), public API, user commands, jump/stage actions
│   ├── config.lua        -- default config + merge
│   ├── git.lua           -- async git calls, raw diff text, staging
│   ├── parser.lua        -- diff text -> FileChange[]/Hunk[]
│   ├── tree.lua          -- FileChange[] -> TreeNode tree, expand/collapse state
│   ├── patch.lua         -- FileChange/Hunk -> unified-diff patch text
│   ├── diffview.lua      -- patch text -> window, via delta or plain filetype=diff
│   ├── ui/
│   │   ├── picker.lua    -- the modal: prompt + filterable list + preview panes
│   │   └── render.lua    -- TreeNode[] -> lines + extmarks (browse/tree mode)
│   └── health.lua        -- :checkhealth gitwalk (git, delta, nvim version)
├── plugin/gitwalk.lua    -- user command registration (thin, guarded by loaded-guard)
├── doc/gitwalk.txt        -- :help gitwalk
├── tests/                -- plenary.nvim busted-style specs
│   ├── parser_spec.lua   -- diff-text fixtures -> expected Hunk[] (pure, no git needed)
│   └── tree_spec.lua
├── README.md
└── LICENSE
```

## 7. Dependencies

- **Required:** Neovim ≥ 0.10 (for `vim.system`), `git` on `$PATH`.
- **Optional:** `nvim-web-devicons` (icons), `plenary.nvim` (only for the test
  suite, not runtime).
- No other runtime deps — keep it a single self-contained plugin, installable
  via lazy.nvim/packer with zero extra `dependencies` for normal use.

## 8. Milestones

1. **Parser core** — `parser.lua` turns `git diff --unified=0` text into
   `Hunk[]`, unit-tested against captured diff fixtures (no live git needed
   to test).
2. **Tree + render** — `tree.lua` + `render.lua`, static buffer output for a
   fixed `FileChange[]` fixture, verifying indentation/collapse logic.
3. **Git wiring** — `git.lua` async collection, wire into tree on `:Gitwalk`.
4. **Navigation + jump** — hunk-aware `j`/`k`, `<CR>` cursor jump, preview
   window with cursor sync.
5. **Polish** — highlights, icons, `stage_hunk`/`stage_file`, refresh on
   autocmds, `:checkhealth`.
6. **Docs + packaging** — `doc/gitwalk.txt`, README with lazy.nvim spec,
   default config table, LICENSE (MIT), CI (github actions running the
   plenary test suite headless).

## 9. Config surface (draft)

```lua
require("gitwalk").setup({
  diff_context = 0,        -- unified context lines used for hunk boundaries
  width = 40,               -- tree panel width
  position = "left",        -- "left" | "right"
  icons = true,
  keymaps = { ... },         -- overridable, see table above
  sign_column = true,
})
```

## 10. Open questions / risks

- Treesitter-based hunk naming: worth doing, but scope it out of v1 so the
  MVP doesn't gain a hard Treesitter-query dependency per filetype.
- Very large diffs (hundreds of hunks): tree render needs to stay a single
  buffer `set_lines` call, not per-node incremental — profile once real.
- Staging individual hunks correctly requires generating a minimal valid
  patch (`git apply --cached --unidiff-zero`) — the trickiest correctness
  surface in the whole plugin; needs deliberate test coverage.

## 11. Next step

This document is the plan only — no code yet. When ready to build, start at
Milestone 1 (`parser.lua` + fixtures), since everything else depends on
correct hunk parsing and it's the one piece testable without a real git repo.
