-- Renders unified-diff patch text into a window: through `delta` for
-- syntax-highlighted, colorized output when it's installed, or a plain
-- `filetype=diff` buffer otherwise.

local M = {}

local delta_checked, delta_available

local function has_delta()
  if delta_checked == nil then
    delta_checked = true
    delta_available = vim.fn.executable("delta") == 1
  end
  return delta_available
end
M.has_delta = has_delta

---termopen gives delta a real pty, so its tty-color-detection kicks in
---without needing to force color flags. The patch is written to a temp
---file and redirected in by the shell rather than sent via chansend(),
---because chansend() immediately followed by chanclose("stdin") races the
---pty's startup and can truncate/drop the write, leaving delta with no
---input.
---@param win integer
---@param patch string
---@param cwd string
---@return integer bufnr
local function render_with_delta(win, patch, cwd)
  local bufnr = vim.api.nvim_create_buf(false, true)
  local width = math.max(vim.api.nvim_win_get_width(win) - 2, 20)
  vim.api.nvim_win_set_buf(win, bufnr)

  local tmpfile = vim.fn.tempname()
  local f = assert(io.open(tmpfile, "w"))
  f:write(patch)
  f:close()

  local cmd = string.format("delta --paging=never --width %d < %s", width, vim.fn.shellescape(tmpfile))
  vim.api.nvim_win_call(win, function()
    vim.fn.termopen(cmd, {
      cwd = cwd,
      on_exit = function()
        os.remove(tmpfile)
      end,
    })
  end)
  vim.wo[win].number = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].wrap = false
  return bufnr
end

---@param win integer
---@param patch string
---@return integer bufnr
local function render_plain(win, patch)
  local bufnr = vim.api.nvim_create_buf(false, true)
  local lines = vim.split(patch, "\n", { plain = true, trimempty = true })
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].filetype = "diff"
  vim.bo[bufnr].modifiable = false
  vim.api.nvim_win_set_buf(win, bufnr)
  vim.wo[win].wrap = false
  vim.wo[win].number = false
  vim.wo[win].signcolumn = "no"
  return bufnr
end

---Render `patch` (a unified diff, e.g. from patch.lua) into floating window
---`win`, replacing whatever buffer it currently shows.
---@param win integer
---@param patch string
---@param cwd string
---@return integer bufnr  the new buffer now shown in `win`
function M.render(win, patch, cwd)
  if has_delta() then
    local ok, bufnr = pcall(render_with_delta, win, patch, cwd)
    if ok then
      return bufnr
    end
  end
  return render_plain(win, patch)
end

return M
