local M = {}

function M.check()
  local health = vim.health or require("health")
  local start = health.start or health.report_start
  local ok = health.ok or health.report_ok
  local error_ = health.error or health.report_error
  local warn = health.warn or health.report_warn

  start("gitwalk.nvim")

  if vim.fn.has("nvim-0.10") == 1 then
    ok("Neovim >= 0.10")
  else
    error_("Neovim >= 0.10 is required (vim.system, vim.uv)")
  end

  if vim.fn.executable("git") == 1 then
    ok("git executable found: " .. vim.fn.exepath("git"))
  else
    error_("git executable not found on $PATH")
  end

  local has_devicons = pcall(require, "nvim-web-devicons")
  if has_devicons then
    ok("nvim-web-devicons found (optional)")
  else
    warn("nvim-web-devicons not found (optional, icons will be plain text)")
  end

  if vim.fn.executable("delta") == 1 then
    ok("delta found: " .. vim.fn.exepath("delta") .. " (preview will be syntax-highlighted)")
  else
    warn("delta not found (optional, https://github.com/dandavison/delta — preview falls back to plain 'filetype=diff' highlighting)")
  end
end

return M
