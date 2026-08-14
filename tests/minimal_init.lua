-- Minimal init for running the test suite headless with plenary.nvim.
-- Usage:
--   nvim --headless -u tests/minimal_init.lua \
--     -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"

local plenary_dir = os.getenv("PLENARY_DIR") or (os.getenv("HOME") .. "/.local/share/nvim/lazy/plenary.nvim")

vim.opt.rtp:append(".")
vim.opt.rtp:append(plenary_dir)

vim.cmd("runtime plugin/plenary.vim")
