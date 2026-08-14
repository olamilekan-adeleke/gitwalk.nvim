# gitwalk.nvim

A Neovim plugin idea: navigate `git diff` as a tree of **hunks**, not files —
so review moves change-by-change, with a live preview and jump-to-exact-line.

```
▼ lib
  ▼ auth
    ▼ login.dart [+17 -4] [3]
      ├─ ① loading state       L18
      ├─ ② authentication      L47
      └─ ③ error handling      L103
```

`j`/`k` moves hunk-to-hunk; `<CR>` drops your cursor on the exact changed
line, not just the top of the file.

## Status

Design/planning stage — see [`PLAN.md`](./PLAN.md) for the full architecture,
data model, module layout, and milestone breakdown. No code yet.

## License

MIT — see [`LICENSE`](./LICENSE).
